// Times a phone's launch (bridge.js, as the apps run it) against a running
// hub, in two runs as the apps do them:
//   bun test/tools/launch_bench.ts <bridge.js> <host:port> <token> cold <state file>
//     first launch: the whole log, then the state kept (Backplane.save)
//   bun test/tools/launch_bench.ts <bridge.js> <host:port> <token> warm <state file>
//     a later launch: script loaded, state loaded, first screen, the
//     hub's catch-up frame, the screen after it
// Run with BUN_JSC_useJIT=0 for phone-like numbers (the apps' engines have
// no JIT).
import { readFileSync, writeFileSync } from "fs";

const [bridge, key, token, mode, file] = process.argv.slice(2);
const ms = (t0: number) => (performance.now() - t0).toFixed(0) + " ms";
let t0 = performance.now();
(0, eval)(readFileSync(bridge, "utf8"));
console.log(`script: ${ms(t0)}`);
const B = (globalThis as any).Backplane;
let screen: any = null;
let ws: WebSocket;
const handle = (text: string) => {
  const o = JSON.parse(text);
  if (o.screen) screen = o.screen;
  for (const c of o.cmds ?? []) if (c.type === "send") ws?.send(Buffer.from(c.data, "base64"));
  return text.length;
};
const rows = () => (screen?.projects ?? []).reduce((n: number, p: any) => n + (p.threads?.length ?? 0), 0);

t0 = performance.now();
handle(B.start("bench", "{}"));
if (mode === "warm") {
  const text = readFileSync(file, "utf8");
  t0 = performance.now();
  const n = handle(B.load(text));
  console.log(`load ${(text.length / 1e6).toFixed(2)} MB state: ${ms(t0)}, screen ${(n / 1e3).toFixed(0)} KB, ${rows()} rows`);
  handle(B.online(key, false, true));
}
t0 = performance.now();
handle(B.hubs([key]));
console.log(`hubs: ${ms(t0)}, ${rows()} rows`);
const r = JSON.parse(B.resume(key));
console.log(`resume since ${r.since} origin ${r.origin}`);
const start = performance.now();
ws = new WebSocket(`ws://${key}/ws?token=${token}&since=${r.since}&origin=${encodeURIComponent(r.origin)}&enc=cbor`);
ws.binaryType = "arraybuffer";
let frames = 0;
let last = Date.now();
ws.onopen = () => handle(B.online(key, true));
ws.onmessage = (m) => {
  const u = new Uint8Array(m.data as ArrayBuffer);
  const t1 = performance.now();
  handle(B.recv(key, Buffer.from(u).toString("base64")));
  if (frames < 3) console.log(`frame ${frames}: ${(u.length / 1e3).toFixed(1)} KB at ${(t1 - start).toFixed(0)} ms, in the client ${ms(t1)}, ${rows()} rows`);
  frames += 1;
  last = Date.now();
};
const sleep = (n: number) => new Promise((r) => setTimeout(r, n));
while (Date.now() - last < 1500 || frames === 0) await sleep(50);
if (mode === "cold") {
  t0 = performance.now();
  const s = B.save();
  writeFileSync(file, s);
  console.log(`save: ${(s.length / 1e6).toFixed(2)} MB in ${ms(t0)}`);
}
ws.close();
process.exit(0);
