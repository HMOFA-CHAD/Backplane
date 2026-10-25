// The secrets vault (server/vault.bend; docs/secrets.md). Values the person
// pasted into the secret box are sealed in <home>/secrets/vault.json
// (0600, folder 0700) with AES-256-GCM, the name as associated data, under
// a 32-byte master key kept in the OS keychain: Secret Service through
// secret-tool on Linux, the login keychain through `security` on macOS,
// DPAPI on Windows; where none answers, <home>/secrets/vault.key (0600).
// The backend is chosen at the first save and written down.
//
// Fail closed: a vault.json that cannot be read, is not JSON, has another
// version or shape, names a secret twice, or holds a value that does not
// open with the key, makes the vault "locked". A locked vault keeps what
// it read (metadata for Settings, every value that did open for masking)
// and refuses every change and every run: nothing is written over the
// evidence and nothing is re-keyed. Only a missing file is a new vault.
//
// Changes are staged: the new items are written to a temporary file,
// flushed and renamed over vault.json; only then do they replace the ones
// in memory (and so the masking set). A failure before the rename leaves
// memory, disk and masking as they were. After it, the folder is flushed:
// a real failure there answers "committed <why>" (saved and in use, not
// claimed durable), and status's flush says what happened last.
//
// Values live decrypted in this file's memory only. Bend gets them for one
// purpose, masking (VaultFx.values -> Sec.vault), and hands names to
// VaultFx.run, which injects them into a child's environment or a 0600
// temp file and masks the child's output with the values it injected (and
// every other) before answering. Nothing here logs, prints or returns a
// value otherwise. BACKPLANE_VAULT_KEYRING=file forces the key file
// (tests); BACKPLANE_VAULT_FAULT=write|fsync|rename|dirsync|dirsync-unsupported makes the next save
// fail at that step (tests only, read with BACKPLANE_VAULT_TEST=1).
const BP_VAULT_BACKENDS = new Set(["keyring", "keychain", "dpapi", "file"]);
const BP_VAULT_NAME = /^[a-z0-9._-]{1,64}$/;
const bp_vault = { home: "", items: new Map(), key: null, backend: "", locked: false, why: "", flush: "", api: { at: 0, mtime: -1, vals: [] } };

function bp_vault_fs() { return require("node:fs"); }
function bp_vault_path(...xs) { return require("node:path").join(bp_vault.home, "secrets", ...xs); }
function bp_vault_id() {
  return require("node:crypto").createHash("sha256").update(bp_vault.home).digest("hex").slice(0, 16);
}

function bp_vault_sh(cmd, args, input) {
  try {
    const r = Bun.spawnSync([cmd, ...args], { stdin: input === undefined ? "ignore" : Buffer.from(input), stdout: "pipe", stderr: "ignore", timeout: 5000, env: process.env });
    return { ok: r.exitCode === 0 && !r.signalCode, out: r.stdout ? r.stdout.toString() : "" };
  } catch (_) {
    return { ok: false, out: "" };
  }
}

function bp_vault_which(cmd) {
  try { return !!Bun.which(cmd); } catch (_) { return false; }
}

// the backend this machine offers, in order of preference
function bp_vault_offer() {
  if (process.env.BACKPLANE_VAULT_KEYRING === "file") return "file";
  if (process.platform === "darwin" && bp_vault_which("security")) return "keychain";
  if (process.platform === "win32") return "dpapi";
  if (bp_vault_which("secret-tool") && (process.env.DBUS_SESSION_BUS_ADDRESS || process.env.XDG_RUNTIME_DIR)) return "keyring";
  return "file";
}

// read the master key from a backend: a Buffer, or null
function bp_vault_key_get(backend) {
  const fs = bp_vault_fs();
  const hex = (s) => { const t = String(s || "").trim(); return /^[0-9a-f]{64}$/.test(t) ? Buffer.from(t, "hex") : null; };
  if (backend === "file") {
    try { return hex(fs.readFileSync(bp_vault_path("vault.key"), "utf8")); } catch (_) { return null; }
  }
  if (backend === "keyring") {
    const r = bp_vault_sh("secret-tool", ["lookup", "service", "backplane-vault", "home", bp_vault_id()]);
    return r.ok ? hex(r.out) : null;
  }
  if (backend === "keychain") {
    const r = bp_vault_sh("security", ["find-generic-password", "-s", "backplane-vault", "-a", bp_vault_id(), "-w"]);
    return r.ok ? hex(r.out) : null;
  }
  if (backend === "dpapi") {
    let blob;
    try { blob = fs.readFileSync(bp_vault_path("vault.key.dpapi"), "utf8").trim(); } catch (_) { return null; }
    const ps = "$b=[Console]::In.ReadToEnd().Trim();Add-Type -AssemblyName System.Security;[Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($b),$null,'CurrentUser'))";
    const r = bp_vault_sh("powershell", ["-NoProfile", "-NonInteractive", "-Command", ps], blob);
    return r.ok ? hex(r.out) : null;
  }
  return null;
}

// keep a new master key in a backend; true when it reads back
function bp_vault_key_put(backend, key) {
  const fs = bp_vault_fs();
  const h = key.toString("hex");
  if (backend === "file") {
    try { fs.writeFileSync(bp_vault_path("vault.key"), h + "\n", { mode: 0o600, flag: "wx" }); } catch (_) { return false; }
  } else if (backend === "keyring") {
    if (!bp_vault_sh("secret-tool", ["store", "--label=Backplane vault", "service", "backplane-vault", "home", bp_vault_id()], h).ok) return false;
  } else if (backend === "keychain") {
    // through security's own prompt on stdin, so the key is never in argv
    if (!bp_vault_sh("security", ["-i"], `add-generic-password -s backplane-vault -a ${bp_vault_id()} -l "Backplane vault" -w ${h}\n`).ok) return false;
  } else if (backend === "dpapi") {
    const ps = "$b=[Console]::In.ReadToEnd().Trim();Add-Type -AssemblyName System.Security;[Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($b),$null,'CurrentUser'))";
    const r = bp_vault_sh("powershell", ["-NoProfile", "-NonInteractive", "-Command", ps], h);
    if (!r.ok || !r.out.trim()) return false;
    try { fs.writeFileSync(bp_vault_path("vault.key.dpapi"), r.out.trim() + "\n", { mode: 0o600, flag: "wx" }); } catch (_) { return false; }
  } else {
    return false;
  }
  const back = bp_vault_key_get(backend);
  return !!back && back.equals(key);
}

function bp_vault_seal(key, name, value) {
  const c = require("node:crypto");
  const iv = c.randomBytes(12);
  const ci = c.createCipheriv("aes-256-gcm", key, iv);
  ci.setAAD(Buffer.from(name));
  const ct = Buffer.concat([ci.update(Buffer.from(value, "utf8")), ci.final()]);
  return { iv: iv.toString("base64"), ct: Buffer.concat([ct, ci.getAuthTag()]).toString("base64") };
}

function bp_vault_open1(key, name, iv, ct) {
  const c = require("node:crypto");
  const all = Buffer.from(ct, "base64");
  if (all.length < 17) throw new Error("short");
  const de = c.createDecipheriv("aes-256-gcm", key, Buffer.from(iv, "base64"));
  de.setAAD(Buffer.from(name));
  de.setAuthTag(all.subarray(all.length - 16));
  return Buffer.concat([de.update(all.subarray(0, all.length - 16)), de.final()]).toString("utf8");
}

function bp_vault_meta(it) {
  return { name: it.name, purpose: it.purpose || "", by: it.by || "", at: it.at || "", usedAt: it.usedAt || "", usedBy: it.usedBy || "" };
}

function bp_vault_fault(step) {
  if (process.env.BACKPLANE_VAULT_TEST !== "1") return;
  const f = process.env.BACKPLANE_VAULT_FAULT;
  if (step === "dirsync" && (f === "dirsync" || f === "dirsync-unsupported")) {
    const e = new Error("injected " + f + " failure");
    e.code = f === "dirsync" ? "EIO" : "EINVAL";
    throw e;
  }
  if (f === step) throw new Error("injected " + step + " failure");
}

// write items as vault.json durably: a temporary file written and flushed,
// renamed over vault.json, the folder flushed. Throws on any failure (the
// temporary file is removed); the caller publishes only after it returns.
function bp_vault_write(items, backend) {
  const fs = bp_vault_fs();
  const list = [...items.values()].map((it) => ({ ...bp_vault_meta(it), iv: it.iv, ct: it.ct }));
  const text = JSON.stringify({ v: 1, key: backend, items: list }, null, 1) + "\n";
  const tmp = bp_vault_path("vault.json." + process.pid + ".tmp");
  fs.mkdirSync(bp_vault_path(), { recursive: true, mode: 0o700 });
  try { fs.chmodSync(bp_vault_path(), 0o700); } catch (_) {}
  let fd = -1;
  try {
    fd = fs.openSync(tmp, "w", 0o600);
    bp_vault_fault("write");
    fs.writeFileSync(fd, text);
    bp_vault_fault("fsync");
    fs.fsyncSync(fd);
    fs.closeSync(fd);
    fd = -1;
    bp_vault_fault("rename");
    fs.renameSync(tmp, bp_vault_path("vault.json"));
  } catch (e) {
    if (fd >= 0) try { fs.closeSync(fd); } catch (_) {}
    try { fs.rmSync(tmp, { force: true }); } catch (_) {}
    throw e;
  }
  // the rename is committed: from here the new items are what is on disk,
  // so the caller publishes them whatever the folder flush says. The flush
  // decides only what is claimed: "durable", "unsupported <code>" (this
  // platform or file system cannot flush a folder: accepted, recorded), or
  // "unflushed <code>" (a real I/O failure: not claimed durable)
  if (process.platform === "win32") return "unsupported win32";
  try {
    const d = fs.openSync(bp_vault_path(), "r");
    try {
      bp_vault_fault("dirsync");
      fs.fsyncSync(d);
    } finally { fs.closeSync(d); }
    return "durable";
  } catch (e) {
    const code = String(e && e.code || "EIO");
    return (["EINVAL", "ENOTSUP", "EOPNOTSUPP", "EISDIR"].includes(code) ? "unsupported " : "unflushed ") + code;
  }
}

// a save's answer from its write's outcome: "ok" when durable (or the
// folder cannot be flushed here), else "committed <why>": saved and in
// use, but not known to survive a crash
function bp_vault_ack(outcome) {
  bp_vault.flush = outcome;
  return outcome.startsWith("unflushed") ? "committed the folder flush failed (" + outcome.slice(10) + "): saved, but not known to survive a crash" : "ok";
}

function bp_vault_lock(why) {
  bp_vault.locked = true;
  if (!bp_vault.why) bp_vault.why = why;
}

// the schema, strictly: {v: 1, key: <backend>, items: [{name, iv, ct,
// purpose?, by?, at?, usedAt?, usedBy?}]}, names unique; "" when it holds
function bp_vault_bad(doc) {
  if (!doc || typeof doc !== "object" || Array.isArray(doc)) return "vault.json is not an object";
  if (doc.v !== 1) return "vault.json has version " + JSON.stringify(doc.v) + ", not 1";
  if (!BP_VAULT_BACKENDS.has(doc.key)) return "vault.json names no known key store";
  if (!Array.isArray(doc.items)) return "vault.json has no item list";
  const seen = new Set();
  for (const it of doc.items) {
    if (!it || typeof it !== "object") return "vault.json has an item that is not an object";
    if (typeof it.name !== "string" || !BP_VAULT_NAME.test(it.name)) return "vault.json has an item without a valid name";
    if (seen.has(it.name)) return "vault.json names " + it.name + " twice";
    seen.add(it.name);
    if (typeof it.iv !== "string" || typeof it.ct !== "string") return "vault.json's " + it.name + " has no sealed value";
    for (const k of ["purpose", "by", "at", "usedAt", "usedBy"]) if (it[k] !== undefined && typeof it[k] !== "string") return "vault.json's " + it.name + " has a bad " + k;
  }
  return "";
}

// VaultFx.open(home): read the vault and its key once; a JSON status
function vault_open(home) {
  bp_vault.home = home;
  bp_vault.items = new Map();
  bp_vault.key = null;
  bp_vault.backend = "";
  bp_vault.locked = false;
  bp_vault.why = "";
  let text = null;
  try {
    text = bp_vault_fs().readFileSync(bp_vault_path("vault.json"), "utf8");
  } catch (e) {
    if (!e || e.code !== "ENOENT") bp_vault_lock("vault.json could not be read (" + String(e && (e.code || e.message) || e) + ")");
  }
  if (text === null) return vault_status();
  let doc;
  try { doc = JSON.parse(text); } catch (_) { bp_vault_lock("vault.json is not valid JSON"); return vault_status(); }
  const bad = bp_vault_bad(doc);
  if (bad) {
    bp_vault_lock(bad);
    // what can be shown is kept for Settings (names only), nothing opened
    if (doc && Array.isArray(doc.items)) for (const it of doc.items) if (it && typeof it.name === "string" && BP_VAULT_NAME.test(it.name) && !bp_vault.items.has(it.name)) bp_vault.items.set(it.name, { ...bp_vault_meta(it), iv: it.iv, ct: it.ct, value: null });
    return vault_status();
  }
  bp_vault.backend = doc.key;
  for (const it of doc.items) bp_vault.items.set(it.name, { ...bp_vault_meta(it), iv: it.iv, ct: it.ct, value: null });
  if (bp_vault.items.size === 0) return vault_status();
  bp_vault.key = bp_vault_key_get(bp_vault.backend);
  if (!bp_vault.key) {
    bp_vault_lock(bp_vault.backend === "file" ? "the vault's key file is missing" : "the " + bp_vault.backend + " did not give the vault's key");
    return vault_status();
  }
  let failed = 0;
  for (const it of bp_vault.items.values()) {
    try { it.value = bp_vault_open1(bp_vault.key, it.name, it.iv, it.ct); } catch (_) { it.value = null; failed++; }
  }
  if (failed) bp_vault_lock(failed + " of " + bp_vault.items.size + " secrets do not open with the vault's key");
  return vault_status();
}

function vault_status() {
  return JSON.stringify({ key: bp_vault.backend || bp_vault_offer(), locked: bp_vault.locked, why: bp_vault.why, n: bp_vault.items.size, flush: bp_vault.flush });
}

// the api.env values too (Settings' API keys), so a key an agent prints
// from that file is masked as well; read again at most once a second
function bp_vault_api() {
  const a = bp_vault.api;
  const now = Date.now();
  if (now - a.at < 1000) return a.vals;
  a.at = now;
  let st;
  try { st = bp_vault_fs().statSync(bp_vault_path("api.env")); } catch (_) { a.vals = []; a.mtime = -1; return a.vals; }
  if (st.mtimeMs === a.mtime) return a.vals;
  a.mtime = st.mtimeMs;
  const vals = [];
  try {
    for (const l of bp_vault_fs().readFileSync(bp_vault_path("api.env"), "utf8").split("\n")) {
      const m = /^[A-Z0-9_]+='(.*)'\s*$/.exec(l);
      if (m) vals.push(m[1].split("'\\''").join("'"));
    }
  } catch (_) {}
  a.vals = vals;
  return a.vals;
}

// every value masked now (vault and api.env), at least 8 characters
function bp_vault_all() {
  const out = [];
  for (const it of bp_vault.items.values()) if (typeof it.value === "string" && it.value.length >= 8) out.push(it.value);
  for (const v of bp_vault_api()) if (v.length >= 8 && !/[\r\n]/.test(v)) out.push(v);
  return out;
}

// VaultFx.values(): every value to mask, one a line (only Bend's masks
// read this; values of under 8 characters would mask ordinary text)
function vault_values() {
  return bp_vault_all().join("\n");
}

// VaultFx.list(): the metadata, a JSON array (never a value)
function vault_list() {
  return JSON.stringify([...bp_vault.items.values()].map(bp_vault_meta));
}

function bp_vault_err(e) {
  return String(e && e.message || e).replace(/[\r\n]/g, " ").slice(0, 200);
}

// VaultFx.put(name, value, purpose, by): "ok" or "fail <why>". Bend has
// checked the name and the value (Sec.bad).
function vault_put(name, value, purpose, by) {
  try {
    if (bp_vault.locked) return "fail the vault is locked: " + bp_vault.why;
    if (!BP_VAULT_NAME.test(name)) return "fail not a secret's name";
    let key = bp_vault.key;
    let backend = bp_vault.backend;
    if (!key) {
      // a new vault (no item yet): its key, from the store chosen now
      backend = backend || bp_vault_offer();
      bp_vault_fs().mkdirSync(bp_vault_path(), { recursive: true, mode: 0o700 });
      key = bp_vault_key_get(backend);
      if (!key) {
        key = require("node:crypto").randomBytes(32);
        if (!bp_vault_key_put(backend, key)) {
          if (backend === "file") return "fail could not keep the vault's key";
          // a keychain that will not take it: the key file instead
          backend = "file";
          const old = bp_vault_key_get("file");
          if (old) key = old;
          else if (!bp_vault_key_put("file", key)) return "fail could not keep the vault's key";
        }
      }
    }
    const old = bp_vault.items.get(name);
    const sealed = bp_vault_seal(key, name, value);
    const staged = new Map(bp_vault.items);
    staged.set(name, { name, purpose: purpose || (old ? old.purpose : ""), by: by || (old ? old.by : ""), at: new Date().toISOString(), usedAt: old ? old.usedAt : "", usedBy: old ? old.usedBy : "", iv: sealed.iv, ct: sealed.ct, value });
    const outcome = bp_vault_write(staged, backend);
    bp_vault.items = staged;
    bp_vault.key = key;
    bp_vault.backend = backend;
    return bp_vault_ack(outcome);
  } catch (e) {
    return "fail " + bp_vault_err(e);
  }
}

// VaultFx.del(name): "ok" or "fail <why>"
function vault_del(name) {
  try {
    if (bp_vault.locked) return "fail the vault is locked: " + bp_vault.why;
    if (!bp_vault.items.has(name)) return "fail no secret named " + name;
    const staged = new Map(bp_vault.items);
    staged.delete(name);
    const outcome = bp_vault_write(staged, bp_vault.backend || bp_vault_offer());
    bp_vault.items = staged;
    return bp_vault_ack(outcome);
  } catch (e) {
    return "fail " + bp_vault_err(e);
  }
}

// The forms of a value masked in a run's output: as it is, JSON-escaped and
// percent-encoded (where they differ), at least 8 characters
function bp_vault_forms(vals) {
  const out = new Set();
  for (const v of vals) {
    if (typeof v !== "string" || v.length < 8) continue;
    out.add(v);
    out.add(JSON.stringify(v).slice(1, -1));
    try { out.add(encodeURIComponent(v)); } catch (_) {}
  }
  return [...out];
}

// every character inside an occurrence of one of the forms, as U+2022
// (Sec.fine's cover; Bend masks again after this with Sec.mask)
function bp_vault_mask(s, forms) {
  if (typeof s !== "string" || s === "" || forms.length === 0) return s;
  const d = new Int32Array(s.length + 1);
  let any = false;
  for (const f of forms) for (let i = s.indexOf(f); i >= 0; i = s.indexOf(f, i + 1)) { d[i]++; d[i + f.length]--; any = true; }
  if (!any) return s;
  let out = "", run = 0;
  for (let i = 0; i < s.length; i++) { run += d[i]; out += run > 0 ? "•" : s[i]; }
  return out;
}

// signal a run's own process group: only a real child's pid (> 1); never
// 0, 1, an empty or a missing pid
function bp_vault_kill(pid, sig) {
  if (!Number.isInteger(pid) || pid <= 1) return false;
  try {
    if (process.platform === "win32") process.kill(pid, sig);
    else process.kill(-pid, sig);
    return true;
  } catch (_) {
    return false;
  }
}

function bp_vault_names(o) {
  const out = [];
  if (o && typeof o === "object") for (const [k, v] of Object.entries(o)) if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(k) && typeof v === "string") out.push([k, v]);
  return out;
}

// a stream's text, keeping only the last cap characters as it goes
function bp_vault_tail(cap) {
  const t = { text: "", cut: 0 };
  t.add = (chunk) => {
    t.text += chunk;
    if (t.text.length > 2 * cap) { t.cut += t.text.length - cap; t.text = t.text.slice(t.text.length - cap); }
  };
  t.done = () => {
    if (t.text.length > cap) { t.cut += t.text.length - cap; t.text = t.text.slice(t.text.length - cap); }
    return t.cut ? "[… " + t.cut + " characters cut]\n" + t.text : t.text;
  };
  return t;
}

// VaultFx.run(spec): runs spec.command (sh -c; cmd /c on Windows) in its
// own process group with each env {VAR: name} in its environment and each
// files {VAR: name} written to a 0600 file in a 0700 folder, VAR its path.
// Output is kept as it streams, the last 64K characters of each. It ends
// when the command and its streams have, or at the timeout: the group is
// sent SIGTERM, then SIGKILL 2 s later, and 3 s after that the run is
// settled whatever still holds its pipes. After the command exits, its
// streams get 2 s, then the group is killed. The temporary folder is
// removed in every case. Answers JSON {code, timedOut, stdout, stderr} or
// {error}, masked with the values this run injected and every value now
// (so a value replaced or deleted during the run stays masked); Bend masks
// it again.
function vault_run(specText, k) {
  let spec;
  try { spec = JSON.parse(specText); } catch (_) { return JSON.stringify({ error: "bad request" }); }
  const use = [...bp_vault_names(spec.env), ...bp_vault_names(spec.files)];
  if (typeof spec.command !== "string" || !spec.command.trim()) return JSON.stringify({ error: "command is required" });
  if (bp_vault.locked) return JSON.stringify({ error: "the vault is locked: " + bp_vault.why });
  for (const [, name] of use) {
    const it = bp_vault.items.get(name);
    if (!it || typeof it.value !== "string") return JSON.stringify({ error: "no secret named " + String(name).slice(0, 64) + " (ask for it with secret_request)" });
  }
  // the run's own masking set: what it injects, held until it answers
  const injected = use.map(([, name]) => bp_vault.items.get(name).value);
  const answer = (o) => {
    const forms = bp_vault_forms(injected.concat(bp_vault_all()));
    const m = {};
    for (const [key, v] of Object.entries(o)) m[key] = typeof v === "string" ? bp_vault_mask(v, forms) : v;
    return JSON.stringify(m);
  };
  const fs = bp_vault_fs();
  const path = require("node:path");
  const env = { ...process.env };
  let dir = "";
  const clean = () => { if (dir) { try { fs.rmSync(dir, { recursive: true, force: true }); } catch (_) {} dir = ""; } };
  try {
    for (const [v, name] of bp_vault_names(spec.env)) env[v] = bp_vault.items.get(name).value;
    if (bp_vault_names(spec.files).length) {
      fs.mkdirSync(bp_vault_path("run"), { recursive: true, mode: 0o700 });
      dir = fs.mkdtempSync(bp_vault_path("run", "r-"));
      fs.chmodSync(dir, 0o700);
      for (const [v, name] of bp_vault_names(spec.files)) {
        const f = path.join(dir, v.toLowerCase());
        fs.writeFileSync(f, bp_vault.items.get(name).value, { mode: 0o600 });
        env[v] = f;
      }
    }
  } catch (e) {
    clean();
    return answer({ error: "could not prepare the run: " + bp_vault_err(e) });
  }
  // last use, written only if the write succeeds (a failure changes nothing)
  try {
    const now = new Date().toISOString();
    const staged = new Map(bp_vault.items);
    for (const [, name] of use) staged.set(name, { ...staged.get(name), usedAt: now, usedBy: String(spec.thread || "") });
    bp_vault_write(staged, bp_vault.backend || bp_vault_offer());
    bp_vault.items = staged;
  } catch (_) {}
  const secs = Math.max(1, Math.min(600, Number(spec.timeout) || 120));
  const win = process.platform === "win32";
  let child;
  try {
    child = require("node:child_process").spawn(win ? "cmd.exe" : "/bin/sh", win ? ["/d", "/s", "/c", spec.command] : ["-c", spec.command], {
      cwd: typeof spec.cwd === "string" && spec.cwd ? spec.cwd : undefined, env, stdio: ["ignore", "pipe", "pipe"], detached: !win, windowsHide: true,
    });
  } catch (e) {
    clean();
    return answer({ error: "could not start: " + bp_vault_err(e) });
  }
  const cap = 65536;
  const out = bp_vault_tail(cap), err = bp_vault_tail(cap);
  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", out.add);
  child.stderr.on("data", err.add);
  const p = new Promise((resolve) => {
    let settled = false, timedOut = false, code = null, open = 2;
    const timers = [];
    const later = (ms, f) => { const t = setTimeout(f, ms); timers.push(t); };
    const settle = (why) => {
      if (settled) return;
      settled = true;
      for (const t of timers) clearTimeout(t);
      try { child.stdout.destroy(); } catch (_) {}
      try { child.stderr.destroy(); } catch (_) {}
      clean();
      resolve(answer(why ? { error: why } : { code: timedOut ? 124 : (code ?? 255), timedOut, stdout: out.done(), stderr: err.done() }));
    };
    const closed = () => { open--; if (open === 0 && code !== null) settle(""); };
    child.stdout.on("close", closed);
    child.stderr.on("close", closed);
    child.on("error", (e) => { if (code === null) settle("the run failed: " + bp_vault_err(e)); });
    child.on("exit", (c, sig) => {
      code = c !== null ? c : 128 + (require("node:os").constants.signals[sig] ?? 0);
      if (open === 0) return settle("");
      // a descendant holds the pipes: 2 s, then the group goes
      later(2000, () => { bp_vault_kill(child.pid, "SIGKILL"); settle(""); });
    });
    later(secs * 1000, () => {
      timedOut = true;
      bp_vault_kill(child.pid, "SIGTERM");
      later(2000, () => bp_vault_kill(child.pid, "SIGKILL"));
      later(5000, () => { if (code === null) code = 124; settle(""); });
    });
  });
  return io_park_promise(p, k, (v, e) => e === undefined ? v : JSON.stringify({ error: "the run failed" }));
}

// the kill guard, reachable by test/tools/secret.mjs only
if (typeof process !== "undefined" && process.env.BACKPLANE_VAULT_TEST === "1") globalThis.BP_VAULT_KILL = bp_vault_kill;

io_eff(CID(VaultFx.open), vault_open);
io_eff(CID(VaultFx.status), vault_status);
io_eff(CID(VaultFx.values), vault_values);
io_eff(CID(VaultFx.list), vault_list);
io_eff(CID(VaultFx.put), vault_put);
io_eff(CID(VaultFx.del), vault_del);
io_eff(CID(VaultFx.run), vault_run);
