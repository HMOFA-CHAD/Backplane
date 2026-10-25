import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync, mkdtempSync, rmSync, existsSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
globalThis.require = require;

// The secret box (src/core/secret.bend, docs/secrets.md): its masks in the
// emitted runtime, the source gate that keeps stored values in their own
// types, and the vault effect against a temporary home.
const root = resolve(dirname(import.meta.filename), '..', '..');
const lib = (await import(pathToFileURL(resolve(process.argv[2])).href)).default;
const BUL = '•';

// 1. masks: no stored value survives, idempotent, length kept, clean text untouched
const vals = ['tskey-auth-k1abcdef', 'ghp_0123456789abcdef', 'abcdabcd', 'cdabcdab', 'xyzxyzxyzxyz'];
const texts = [
  '', 'nothing here', 'key is tskey-auth-k1abcdef ok', 'tskey-auth-k1abcdeftskey-auth-k1abcdef',
  'x ghp_0123456789abcdef y ghp_0123456789abcdef', 'abcdabcdabcdab', 'zzabcdabcdabzz', 'xyzxyzxyzxyzxyzxyz',
  '{"text":"tskey-auth-k1abcdef"}', 'tskey-auth-k1abcde', 'ünïcödé tskey-auth-k1abcdef 🦋',
];
const rnd = (n) => { let s = ''; const a = 'abcdxyz-_tskeyghp0123'; for (let i = 0; i < n; i++) s += a[Math.floor(Math.random() * a.length)]; return s; };
for (let i = 0; i < 200; i++) texts.push(rnd(5) + vals[i % vals.length] + rnd(7) + vals[(i * 3) % vals.length].slice(2) + rnd(3));
const vs = vals.join('\n');
for (const t of texts) {
  const m = lib.mask(vs, t);
  for (const v of vals) assert.ok(!m.includes(v), `a value survived in ${JSON.stringify(m)}`);
  assert.equal(lib.clean(vs, m), true);
  assert.equal(lib.mask(vs, m), m, 'masking twice is masking once');
  assert.equal([...m].length, [...t].length, 'the length is kept');
  if (!vals.some((v) => t.includes(v))) assert.equal(m, t, 'clean text is left alone');
  // only covered characters change, and they become bullets
  const a = [...t], b = [...m];
  for (let k = 0; k < a.length; k++) if (a[k] !== b[k]) assert.equal(b[k], BUL);
}
assert.equal(lib.mask('', 'tskey-auth-k1abcdef'), 'tskey-auth-k1abcdef', 'an empty vault masks nothing');
assert.equal(lib.mask(vs, 'see tskey-auth-k1abcdef.'), 'see ' + BUL.repeat(19) + '.');

// JSON: every string and key masked; numbers and structure kept
const j = '{"a":"tskey-auth-k1abcdef","tskey-auth-k1abcdef":1,"l":["ok","x abcdabcd"],"n":12}';
const jm = lib.json(vs, j);
assert.ok(!vals.some((v) => jm.includes(v)), jm);
assert.equal(lib.json_clean(vs, j), true);
assert.deepEqual(Object.values(JSON.parse(jm)).length, 4);
assert.equal(JSON.parse(jm).n, 12);
assert.equal(lib.json(vs, '{"a":"fine"}'), '{"a":"fine"}');

// names, values, handles, the request the host sends
assert.equal(lib.name('Tailscale Bub'), 'tailscale-bub');
assert.equal(lib.name('  GH_token.v2  '), 'gh_token.v2');
assert.equal(lib.bad('x', 'short'), 'A secret is at least 8 characters');
assert.equal(lib.bad('', 'tskey-auth-k1abcdef'), 'Give the secret a name');
assert.match(lib.bad('x', 'has space inside'), /no spaces/);
assert.match(lib.bad('x', 'has"quote1'), /quotes/);
assert.equal(lib.bad('x', 'tskey-auth-k1abcdef'), '');
assert.equal(lib.handle('tailscale-bub'), '{"secret":"tailscale-bub","set":true}');
const ok = JSON.parse(lib.req('Tailscale Bub\u001fjoin the tailnet\u001ft1\u001f tskey-auth-k1abcdef '));
assert.equal(ok.name, 'tailscale-bub');
const rpc = JSON.parse(ok.rpc);
assert.equal(rpc.m, 'secret.set');
assert.deepEqual(rpc.p, { name: 'tailscale-bub', purpose: 'join the tailnet', thread: 't1', value: 'tskey-auth-k1abcdef' });
assert.match(JSON.parse(lib.req('n\u001fp\u001ft\u001fshort')).error, /at least 8/);
assert.ok(JSON.parse(lib.req('garbage')).error);
const pr = lib.prompt('[{"name":"tailscale-bub","purpose":"p"}]');
assert.match(pr, /`tailscale-bub`/);
assert.match(pr, /secret_request/);
assert.ok(!lib.prompt('[]').includes('Set now'));

// 2. the source gate: SecVal{ and Vault{ are built or taken apart only in
// secret.bend, vault.bend and the proofs, and no other type names them in
// a field (so no Change, mail, prompt, render or tool-result constructor
// can hold a stored value)
const allowed = new Set(['src/core/secret.bend', 'src/server/vault.bend', 'test/secret_proof.bend', 'test/secret_test.bend', 'LAWS.bend', 'PROOF.bend']);
const walk = (d, out = []) => {
  for (const n of readdirSync(join(root, d))) {
    if (n.startsWith('.') || n === 'node_modules' || n === 'build' || n === 'dist') continue;
    const p = join(d, n);
    const st = statSync(join(root, p));
    if (st.isDirectory()) walk(p, out);
    else if (n.endsWith('.bend')) out.push(p);
  }
  return out;
};
const files = ['src', 'test'].flatMap((d) => walk(d)).concat(['LAWS.bend', 'PROOF.bend']);
for (const f of files) {
  if (allowed.has(f)) continue;
  const text = readFileSync(join(root, f), 'utf8');
  assert.ok(!/\bSecVal\s*\{/.test(text), `${f} builds or matches a SecVal`);
  assert.ok(!/\.Vault\s*\{/.test(text) && !/(^|[^.\w])Vault\s*\{/m.test(text), `${f} builds or matches a Vault`);
  // a field typed SecVal or Vault in any other type
  for (const m of text.matchAll(/^type [^\n]*\n((?:  [^\n]*\n)+)/gm)) {
    assert.ok(!/:\s*[\w.]*\b(SecVal|Vault)\b/.test(m[1]), `${f}: a type holds a stored value: ${m[0].split('\n')[0]}`);
  }
}

// 3. the vault effect against a temporary home (file key)
const home = mkdtempSync(join(tmpdir(), 'bp-vault-'));
try {
  const effects = {};
  globalThis.io_eff = (id, fn) => { effects[id] = fn; };
  globalThis.CID = (x) => x;
  globalThis.io_park_promise = (p, k, then) => p.then((v) => then(v), (e) => then(undefined, e));
  globalThis.VaultFx = new Proxy({}, { get: (_, n) => n });
  process.env.BACKPLANE_VAULT_KEYRING = 'file';
  new Function(readFileSync(join(root, 'src/server/effects/vault.js'), 'utf8'))();
  const st = JSON.parse(effects.open(home));
  assert.equal(st.n, 0);
  assert.equal(effects.values(), '');
  assert.equal(effects.put('tailscale-bub', 'tskey-auth-k1abcdef', 'join', 'person'), 'ok');
  assert.equal(effects.put('gh', 'ghp_0123456789abcdef', '', 'person'), 'ok');
  const disk = readFileSync(join(home, 'secrets', 'vault.json'), 'utf8');
  assert.ok(!disk.includes('tskey-auth-k1abcdef') && !disk.includes('ghp_0123456789abcdef'), 'sealed at rest');
  assert.equal(statSync(join(home, 'secrets', 'vault.json')).mode & 0o777, 0o600);
  assert.equal(statSync(join(home, 'secrets', 'vault.key')).mode & 0o777, 0o600);
  assert.equal(statSync(join(home, 'secrets')).mode & 0o777, 0o700);
  const list = JSON.parse(effects.list());
  assert.deepEqual(list.map((m) => m.name).sort(), ['gh', 'tailscale-bub']);
  assert.ok(!JSON.stringify(list).includes('tskey'), 'the list carries no value');
  // reopened from disk: the values come back for masking only
  assert.equal(JSON.parse(effects.open(home)).n, 2);
  assert.deepEqual(effects.values().split('\n').sort(), ['ghp_0123456789abcdef', 'tskey-auth-k1abcdef']);
  // a run: env and a 0600 file, removed after; the answer is raw here (Bend masks it)
  const r = JSON.parse(await effects.run(JSON.stringify({ command: 'test "$TS" = tskey-auth-k1abcdef && stat -c %a "$GH" && cat "$GH"', env: { TS: 'tailscale-bub' }, files: { GH: 'gh' }, cwd: home, thread: 't1' }), null));
  assert.equal(r.code, 0, JSON.stringify(r));
  assert.match(r.stdout, /^600\nghp_0123456789abcdef$/);
  assert.equal(readdirSync(join(home, 'secrets', 'run')).length, 0, 'temp files removed');
  assert.equal(JSON.parse(effects.list()).find((m) => m.name === 'gh').usedBy, 't1');
  assert.match(JSON.parse(await effects.run(JSON.stringify({ command: 'true', env: { X: 'nope' } }), null)).error, /no secret named nope/);
  // a swapped ciphertext does not open (the name is bound in)
  const doc = JSON.parse(readFileSync(join(home, 'secrets', 'vault.json'), 'utf8'));
  [doc.items[0].ct, doc.items[1].ct] = [doc.items[1].ct, doc.items[0].ct];
  [doc.items[0].iv, doc.items[1].iv] = [doc.items[1].iv, doc.items[0].iv];
  require('node:fs').writeFileSync(join(home, 'secrets', 'vault.json'), JSON.stringify(doc));
  effects.open(home);
  assert.equal(effects.values(), '', 'swapped values do not decrypt');
  // the key gone: locked, never re-keyed
  rmSync(join(home, 'secrets', 'vault.key'));
  const locked = JSON.parse(effects.open(home));
  assert.equal(locked.locked, true);
  assert.match(effects.put('x', 'abcdefghij', '', ''), /^fail the vault is locked/);
  assert.equal(effects.del('gh'), 'ok');
  assert.ok(!existsSync(join(home, 'secrets', 'vault.key')));
} finally {
  rmSync(home, { recursive: true, force: true });
}
console.log('secret: ok');
