// The secrets vault (server/vault.bend; docs/secrets.md). Values the person
// pasted into the secret box are sealed in <home>/secrets/vault.json
// (0600, folder 0700) with AES-256-GCM, the name as associated data, under
// a 32-byte master key kept in the OS keychain: Secret Service through
// secret-tool on Linux, the login keychain through `security` on macOS,
// DPAPI on Windows; where none answers, <home>/secrets/vault.key (0600).
// The backend is chosen at the first save and written down; if it stops
// answering the vault is "locked", never re-keyed.
//
// Values live decrypted in this file's memory only. Bend gets them for one
// purpose, masking (VaultFx.values -> Sec.vault), and hands names to
// VaultFx.run, which injects them into a child's environment or a 0600
// temp file. Nothing here logs, prints or returns a value otherwise.
// BACKPLANE_VAULT_KEYRING=file forces the key file (tests).
const bp_vault = { home: "", items: new Map(), key: null, backend: "", locked: false, why: "", api: { at: 0, mtime: -1, vals: [] } };

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
    try { fs.writeFileSync(bp_vault_path("vault.key"), h + "\n", { mode: 0o600 }); fs.chmodSync(bp_vault_path("vault.key"), 0o600); } catch (_) { return false; }
  } else if (backend === "keyring") {
    if (!bp_vault_sh("secret-tool", ["store", "--label=Backplane vault", "service", "backplane-vault", "home", bp_vault_id()], h).ok) return false;
  } else if (backend === "keychain") {
    // through security's own prompt on stdin, so the key is never in argv
    if (!bp_vault_sh("security", ["-i"], `add-generic-password -U -s backplane-vault -a ${bp_vault_id()} -l "Backplane vault" -w ${h}\n`).ok) return false;
  } else if (backend === "dpapi") {
    const ps = "$b=[Console]::In.ReadToEnd().Trim();Add-Type -AssemblyName System.Security;[Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($b),$null,'CurrentUser'))";
    const r = bp_vault_sh("powershell", ["-NoProfile", "-NonInteractive", "-Command", ps], h);
    if (!r.ok || !r.out.trim()) return false;
    try { fs.writeFileSync(bp_vault_path("vault.key.dpapi"), r.out.trim() + "\n", { mode: 0o600 }); } catch (_) { return false; }
  } else {
    return false;
  }
  const back = bp_vault_key_get(backend);
  return !!back && back.equals(key);
}

function bp_vault_seal(name, value) {
  const c = require("node:crypto");
  const iv = c.randomBytes(12);
  const ci = c.createCipheriv("aes-256-gcm", bp_vault.key, iv);
  ci.setAAD(Buffer.from(name));
  const ct = Buffer.concat([ci.update(Buffer.from(value, "utf8")), ci.final()]);
  return { iv: iv.toString("base64"), ct: Buffer.concat([ct, ci.getAuthTag()]).toString("base64") };
}

function bp_vault_open1(name, iv, ct) {
  const c = require("node:crypto");
  const all = Buffer.from(ct, "base64");
  const de = c.createDecipheriv("aes-256-gcm", bp_vault.key, Buffer.from(iv, "base64"));
  de.setAAD(Buffer.from(name));
  de.setAuthTag(all.subarray(all.length - 16));
  return Buffer.concat([de.update(all.subarray(0, all.length - 16)), de.final()]).toString("utf8");
}

function bp_vault_meta(it) {
  return { name: it.name, purpose: it.purpose || "", by: it.by || "", at: it.at || "", usedAt: it.usedAt || "", usedBy: it.usedBy || "" };
}

// write vault.json atomically (0600 in a 0700 folder)
function bp_vault_save() {
  const fs = bp_vault_fs();
  const items = [...bp_vault.items.values()].map((it) => ({ ...bp_vault_meta(it), iv: it.iv, ct: it.ct }));
  const text = JSON.stringify({ v: 1, key: bp_vault.backend, items }, null, 1) + "\n";
  const tmp = bp_vault_path("vault.json.tmp");
  fs.mkdirSync(bp_vault_path(), { recursive: true, mode: 0o700 });
  try { fs.chmodSync(bp_vault_path(), 0o700); } catch (_) {}
  fs.writeFileSync(tmp, text, { mode: 0o600 });
  fs.renameSync(tmp, bp_vault_path("vault.json"));
}

// VaultFx.open(home): read the vault and its key once; a JSON status
function vault_open(home) {
  bp_vault.home = home;
  bp_vault.items = new Map();
  bp_vault.key = null;
  bp_vault.locked = false;
  bp_vault.why = "";
  let doc = null;
  try { doc = JSON.parse(bp_vault_fs().readFileSync(bp_vault_path("vault.json"), "utf8")); } catch (_) {}
  bp_vault.backend = doc && typeof doc.key === "string" ? doc.key : "";
  if (doc && Array.isArray(doc.items)) {
    for (const it of doc.items) if (it && typeof it.name === "string") bp_vault.items.set(it.name, { ...bp_vault_meta(it), iv: it.iv, ct: it.ct, value: null });
  }
  if (bp_vault.items.size > 0) {
    bp_vault.key = bp_vault_key_get(bp_vault.backend);
    if (!bp_vault.key) {
      bp_vault.locked = true;
      bp_vault.why = bp_vault.backend === "file" ? "the vault's key file is missing" : "the " + bp_vault.backend + " did not give the vault's key";
    } else {
      for (const it of bp_vault.items.values()) {
        try { it.value = bp_vault_open1(it.name, it.iv, it.ct); } catch (_) { it.value = null; }
      }
    }
  }
  return vault_status();
}

function vault_status() {
  return JSON.stringify({ key: bp_vault.backend || bp_vault_offer(), locked: bp_vault.locked, why: bp_vault.why, n: bp_vault.items.size });
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

// VaultFx.values(): every value to mask, one a line (only Bend's masks
// read this; values of under 8 characters would mask ordinary text)
function vault_values() {
  const out = [];
  for (const it of bp_vault.items.values()) if (typeof it.value === "string" && it.value.length >= 8) out.push(it.value);
  for (const v of bp_vault_api()) if (v.length >= 8 && !/[\r\n]/.test(v)) out.push(v);
  return out.join("\n");
}

// VaultFx.list(): the metadata, a JSON array (never a value)
function vault_list() {
  return JSON.stringify([...bp_vault.items.values()].filter((it) => typeof it.value === "string" || bp_vault.locked).map(bp_vault_meta));
}

// VaultFx.put(name, value, purpose, by): "ok" or "fail <why>". Bend has
// checked the name and the value (Sec.bad).
function vault_put(name, value, purpose, by) {
  try {
    if (bp_vault.locked) return "fail the vault is locked: " + bp_vault.why;
    if (!bp_vault.key) {
      const backend = bp_vault.backend || bp_vault_offer();
      const fs = bp_vault_fs();
      fs.mkdirSync(bp_vault_path(), { recursive: true, mode: 0o700 });
      let key = bp_vault_key_get(backend);
      if (!key) {
        key = require("node:crypto").randomBytes(32);
        if (!bp_vault_key_put(backend, key)) {
          if (backend === "file" || bp_vault.items.size > 0) return "fail could not keep the vault's key";
          // a keychain that will not take it: the key file instead
          if (!bp_vault_key_put("file", key)) return "fail could not keep the vault's key";
          bp_vault.backend = "file";
        } else {
          bp_vault.backend = backend;
        }
      } else {
        bp_vault.backend = backend;
      }
      bp_vault.key = key;
    }
    const old = bp_vault.items.get(name);
    const sealed = bp_vault_seal(name, value);
    bp_vault.items.set(name, { name, purpose: purpose || (old ? old.purpose : ""), by: by || (old ? old.by : ""), at: new Date().toISOString(), usedAt: old ? old.usedAt : "", usedBy: old ? old.usedBy : "", iv: sealed.iv, ct: sealed.ct, value });
    bp_vault_save();
    return "ok";
  } catch (e) {
    return "fail " + String(e && e.message || e).replace(/[\r\n]/g, " ").slice(0, 200);
  }
}

// VaultFx.del(name): "ok" or "fail <why>"
function vault_del(name) {
  try {
    if (!bp_vault.items.delete(name)) return "fail no secret named " + name;
    bp_vault_save();
    return "ok";
  } catch (e) {
    return "fail " + String(e && e.message || e).replace(/[\r\n]/g, " ").slice(0, 200);
  }
}

function bp_vault_names(o) {
  const out = [];
  if (o && typeof o === "object") for (const [k, v] of Object.entries(o)) if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(k) && typeof v === "string") out.push([k, v]);
  return out;
}

// VaultFx.run(spec): runs spec.command (sh -c; cmd /c on Windows) with
// each env {VAR: name} in its environment and each files {VAR: name}
// written to a 0600 file in a 0700 folder removed after the run, VAR its
// path. Answers JSON {code, stdout, stderr} or {error}; Bend masks it
// before an agent sees it. Parks until the child ends or times out.
function vault_run(specText, k) {
  let spec;
  try { spec = JSON.parse(specText); } catch (_) { return JSON.stringify({ error: "bad request" }); }
  const env = { ...process.env };
  const use = [...bp_vault_names(spec.env), ...bp_vault_names(spec.files)];
  if (typeof spec.command !== "string" || !spec.command.trim()) return JSON.stringify({ error: "command is required" });
  if (bp_vault.locked) return JSON.stringify({ error: "the vault is locked: " + bp_vault.why });
  for (const [, name] of use) {
    const it = bp_vault.items.get(name);
    if (!it || typeof it.value !== "string") return JSON.stringify({ error: "no secret named " + name + " (ask for it with secret_request)" });
  }
  const fs = bp_vault_fs();
  const path = require("node:path");
  let dir = "";
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
    if (dir) try { fs.rmSync(dir, { recursive: true, force: true }); } catch (_) {}
    return JSON.stringify({ error: "could not prepare the run: " + String(e && e.message || e).slice(0, 200) });
  }
  const now = new Date().toISOString();
  for (const [, name] of use) { const it = bp_vault.items.get(name); it.usedAt = now; it.usedBy = String(spec.thread || ""); }
  try { bp_vault_save(); } catch (_) {}
  const secs = Math.max(1, Math.min(600, Number(spec.timeout) || 120));
  const argv = process.platform === "win32" ? ["cmd.exe", "/d", "/s", "/c", spec.command] : ["/bin/sh", "-c", spec.command];
  let child;
  try {
    child = Bun.spawn(argv, { cwd: typeof spec.cwd === "string" && spec.cwd ? spec.cwd : undefined, env, stdin: "ignore", stdout: "pipe", stderr: "pipe" });
  } catch (e) {
    if (dir) try { fs.rmSync(dir, { recursive: true, force: true }); } catch (_) {}
    return JSON.stringify({ error: "could not start: " + String(e && e.message || e).slice(0, 200) });
  }
  const cap = 65536;
  const tail = (s) => s.length > cap ? "[… " + (s.length - cap) + " characters cut]\n" + s.slice(s.length - cap) : s;
  let timedOut = false;
  const timer = setTimeout(() => { timedOut = true; try { child.kill(); } catch (_) {} }, secs * 1000);
  const p = Promise.all([new Response(child.stdout).text(), new Response(child.stderr).text(), child.exited]).then(([out, err, code]) => {
    clearTimeout(timer);
    if (dir) try { fs.rmSync(dir, { recursive: true, force: true }); } catch (_) {}
    return JSON.stringify({ code: timedOut ? 124 : (code ?? 255), timedOut, stdout: tail(out), stderr: tail(err) });
  }, (e) => {
    clearTimeout(timer);
    if (dir) try { fs.rmSync(dir, { recursive: true, force: true }); } catch (_) {}
    return JSON.stringify({ error: String(e && e.message || e).slice(0, 200) });
  });
  return io_park_promise(p, k, (v, err) => err === undefined ? v : JSON.stringify({ error: "the run failed" }));
}

io_eff(CID(VaultFx.open), vault_open);
io_eff(CID(VaultFx.status), vault_status);
io_eff(CID(VaultFx.values), vault_values);
io_eff(CID(VaultFx.list), vault_list);
io_eff(CID(VaultFx.put), vault_put);
io_eff(CID(VaultFx.del), vault_del);
io_eff(CID(VaultFx.run), vault_run);
