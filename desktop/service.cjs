const fs = require('node:fs/promises');
const path = require('node:path');
const net = require('node:net');
const { spawn } = require('node:child_process');
const { createHash } = require('node:crypto');

// /hello is the existing service's small CBOR map. Do not pull the domain
// model into Electron or attempt to decode its event stream here.
function hello(bytes) {
  let i = 0;
  function read() {
    const b = bytes[i++], major = b >> 5, add = b & 31;
    let n = add;
    if (add === 24) n = bytes[i++];
    else if (add === 25) { n = bytes.readUInt16BE(i); i += 2; }
    else if (add === 26) { n = bytes.readUInt32BE(i); i += 4; }
    else if (add > 26) throw new Error('Unsupported service greeting');
    if (major === 0) return n;
    if (major === 3) { const s = bytes.subarray(i, i + n).toString('utf8'); i += n; return s; }
    if (major === 5) { const o = {}; for (let j = 0; j < n; j++) o[read()] = read(); return o; }
    throw new Error('Invalid service greeting');
  }
  const result = read();
  if (i !== bytes.length || !result.backplane || typeof result.backplane !== 'string') throw new Error('Not a Backplane service');
  return result;
}
function lockLine(text) {
  const match = /^(\d+) (\d+) flock\s*$/.exec(text);
  if (!match || +match[1] < 1 || +match[2] < 1 || +match[2] > 65535) throw Object.assign(new Error('Invalid service lock'), { code: 'ERR_SERVICE_LOCK' });
  return { posixPid: +match[1], port: +match[2] };
}
async function greeting(origin) {
  const response = await fetch(`${origin}/hello`, { signal: AbortSignal.timeout(1500), redirect: 'error' });
  if (!response.ok) throw Object.assign(new Error('Service greeting failed'), { code: response.status === 503 ? 'ERR_SERVICE_BUSY' : 'ERR_SERVICE_GREETING' });
  const bytes = Buffer.from(await response.arrayBuffer());
  if (bytes.length > 4096) throw new Error('Service greeting too large');
  return hello(bytes);
}
async function freePort(preferred = 0) {
  const server = net.createServer();
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(preferred, '127.0.0.1', () => { const port = server.address().port; server.close(() => resolve(port)); });
  });
}
function preferredPort(home) {
  // Origin is part of the browser cache boundary. An owned service should
  // return to the same loopback origin after an ordinary app-process restart.
  return 30000 + createHash('sha256').update(path.resolve(home)).digest().readUInt32BE(0) % 30000;
}
async function servicePort(home) {
  try { return await freePort(preferredPort(home)); }
  catch (error) { if (error.code !== 'EADDRINUSE') throw error;return freePort(); }
}
class Service {
  constructor({ home, binary, web, expectedVersion }) {
    if (!path.isAbsolute(home)) throw new Error('BACKPLANE_HOME must be absolute');
    this.home = path.resolve(home); this.binary = binary; this.web = web; this.expectedVersion = expectedVersion;
    this.child = null;
  }
  async discover() {
    let line;
    try { line = await fs.readFile(path.join(this.home, 'hub.lock'), 'utf8'); }
    catch (error) { if (error.code === 'ENOENT') return null; throw error; }
    const lock = lockLine(line);
    const origin = `http://127.0.0.1:${lock.port}`;
    let info;
    try { info = await greeting(origin); }
    catch (error) { if (error.cause?.code === 'ECONNREFUSED') return null; throw error; }
    if (this.expectedVersion && info.backplane !== this.expectedVersion) throw new Error('Service version differs from the packaged version');
    // Authenticating with this home's credential binds the discovered endpoint
    // to the selected home. The legacy lock PID is POSIX (including Cygwin),
    // never a Node/Win32 process identity and never a target for signalling.
    const paired = await fetch(`${origin}/auth/pair`, { method: 'POST', redirect: 'error', signal: AbortSignal.timeout(1500), headers: { Authorization: `Bearer ${await this.token()}` } });
    if (!paired.ok) throw new Error('Discovered service does not authenticate for this home');
    return { origin, version: info.backplane, lockIdentity: { posixPid: lock.posixPid } };
  }
  async start() {
    await fs.mkdir(this.home, { recursive: true, mode: 0o700 });
    const deadline = Date.now() + 45000;
    // A listening service can still be recovering a large log. Keep the local
    // window visible while waiting; a busy endpoint is not permission to spawn.
    while (true) {
      try {
        const existing = await this.discover();
        if (existing) return this.connection = existing;
        break;
      } catch (error) {
        if (!['ERR_SERVICE_BUSY', 'TimeoutError'].includes(error.code ?? error.name) || Date.now() >= deadline) throw error;
        await new Promise(resolve => setTimeout(resolve, 100));
      }
    }
    if (!this.binary || !path.isAbsolute(this.binary) || !this.web || !path.isAbsolute(this.web)) throw new Error('Set absolute BACKPLANE_SERVICE and BACKPLANE_WEB paths');
    const port = await servicePort(this.home);
    const args = ['--home', this.home, '--port', String(port), '--host', '127.0.0.1', '--web', this.web, '--foreground', '--no-tailscale'];
    this.child = spawn(this.binary, args, { stdio: ['ignore', 'ignore', 'ignore'], env: { ...process.env, BACKPLANE_HOME: this.home }, windowsHide: true, detached: true });
    this.child.unref();
    let failure;
    this.child.once('error', () => { failure = new Error('Cannot start the packaged service'); });
    this.child.once('exit', code => { failure = new Error(`Service exited (${code})`); });
    while (Date.now() < deadline) {
      if (failure) throw failure;
      try {
        const connection = await this.discover();
        if (connection) {
          // Retain our captured native child handle even when another launcher
          // won the home lock. A losing child exits on its own. Lock-file PID
          // equality is not an ownership test (Cygwin IDs differ on Windows).
          return this.connection = connection;
        }
      } catch (error) {
        if (!['ECONNREFUSED', 'ENOENT', 'ERR_SERVICE_LOCK', 'ERR_SERVICE_BUSY', 'TimeoutError'].includes(error.cause?.code ?? error.code ?? error.name) && error.message !== 'fetch failed') throw error;
      }
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    throw new Error('Service readiness timed out');
  }
  async token() {
    const token = (await fs.readFile(path.join(this.home, 'token'), 'utf8')).trim();
    if (!/^[0-9a-f]{32}$/.test(token)) throw new Error('Invalid service credential');
    return token;
  }
  stop() {
    // Only the child captured here is ours. Never signal a discovered service.
    if (this.child && this.child.exitCode === null) {
      if (process.platform === 'win32') throw new Error('Explicit Windows service shutdown needs the approved service protocol');
      this.child.kill('SIGTERM');
    }
    this.child = null;
  }
}
module.exports = { Service, hello, lockLine, preferredPort, servicePort };
