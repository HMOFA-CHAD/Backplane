// Read-only native protocol smoke. No pairing exchange, credential changes or
// actions. Usage: bun test/ios-connection/live-probe.mjs https://hub [token-file]
// Prints timings, booleans and allowlisted error codes; never payloads or URLs.
import {readFileSync} from 'node:fs';
import {homedir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {cbor, plain} from '../../src/web/wire.js';
import {ThinViews} from '../../src/web/thin.js';

function encode(value, out = []) {
  const head = (kind, n) => {
    if (n < 24) out.push(kind | n);
    else if (n < 256) out.push(kind | 24, n);
    else if (n < 65536) out.push(kind | 25, n >> 8, n & 255);
    else out.push(kind | 26, n >>> 24, (n >>> 16) & 255, (n >>> 8) & 255, n & 255);
  };
  if (value === null) out.push(246);
  else if (typeof value === 'boolean') out.push(value ? 245 : 244);
  else if (typeof value === 'number') {
    if (Number.isInteger(value) && value >= 0 && value < 2 ** 32) head(0, value);
    else { out.push(199); encode(String(value), out); }
  } else if (typeof value === 'string') {
    const bytes = new TextEncoder().encode(value); head(96, bytes.length);
    for (const byte of bytes) out.push(byte);
  } else if (Array.isArray(value)) { head(128, value.length); for (const item of value) encode(item, out); }
  else { const fields = Object.entries(value); head(160, fields.length); for (const [k, v] of fields) { encode(k, out); encode(v, out); } }
  return out;
}

const report = {};
try {
  const base = new URL(process.argv[2]);
  if (!['http:', 'https:'].includes(base.protocol) || base.username || base.password || base.search || base.hash || base.pathname !== '/') throw 0;
  const token = readFileSync(process.argv[3] || homedir() + '/.backplane-bend/token', 'utf8').trim();
  const source = readFileSync(fileURLToPath(new URL('../../src/core/cbor.bend', import.meta.url)), 'utf8');
  const dictionary = name => JSON.parse(source.match(new RegExp('def Cbor.' + name + '\\(\\).*?:\\n\\s*(\\[[\\s\\S]*?\\])'))[1]);
  const meta = {keys:dictionary('keys'), words:dictionary('words')};
  let began = Date.now();
  const cap = await fetch(new URL('/client/capabilities', base), {headers:{Authorization:'Bearer ' + token}, redirect:'manual', signal:AbortSignal.timeout(10000)});
  report.capabilityStatus = cap.status; report.capabilityMs = Date.now() - began;
  if (cap.status !== 200) throw 0;
  const capability = await cap.json();
  report.mobileCapability = capability?.views?.version === 1 && capability?.views?.renderers?.includes('mobile');
  if (!report.mobileCapability) throw 0;
  await new Promise((resolve, reject) => {
    began = Date.now();
    const url = new URL('/ws', base); url.protocol = base.protocol === 'https:' ? 'wss:' : 'ws:';
    url.search = new URLSearchParams({token, since:'0', origin:'', enc:'cbor', view:'1', mobile:'1'}).toString();
    const socket = new WebSocket(url); socket.binaryType = 'arraybuffer';
    const timer = setTimeout(() => { report.timedOut = true; socket.close(); reject(0); }, 7000);
    const done = ok => { clearTimeout(timer); socket.close(); ok ? resolve() : reject(0); };
    const client = new ThinViews({now:()=>Date.now(), send:(_hub, request)=>request, command:()=>{ throw 0; }});
    let requestId;
    socket.onmessage = event => {
      try {
        const frame = plain(cbor(new Uint8Array(event.data), meta.keys, meta.words));
        if (frame.t === 'view') {
          report.greetingAccepted = client.connect(base.host, frame).connected === true;
          report.greetingMs = Date.now() - began;
          if (!report.greetingAccepted) return done(false);
          const selected = client.select(base.host, {kind:'recent', id:''},
            {sel:'', rid:1, drafts:{}, open:{}, info:{}, adding:false, panel:false}, 'native-readonly-diagnostic');
          const request = selected.cmds[0]; requestId = request.id;
          socket.send(new Uint8Array(encode({...request, p:{...request.p, nativeRenderer:'ios-v1'}})));
        } else if (frame.t === 'reply' && frame.id === requestId) {
          report.readOK = frame.ok === true; report.readMs = Date.now() - began; report.readBytes = event.data.byteLength;
          if (frame.ok !== true) {
            const code = frame.error?.code;
            report.errorCode = ['LIMIT','NOT_READY','BAD_REQUEST','STALE_CURSOR','STALE_VIEW','UNAVAILABLE','UNSUPPORTED'].includes(code) ? code : 'OTHER';
          } else { report.remoteReady = frame.result?.remoteReady === true; report.mobileRenderer = frame.result?.renderer === 'mobile'; }
          done(frame.ok === true && report.remoteReady && report.mobileRenderer);
        }
      } catch { report.protocolFailure = true; done(false); }
    };
    socket.onerror = () => { report.socketFailure = true; done(false); };
  });
} catch { process.exitCode = 1; }
console.log(JSON.stringify(report));
