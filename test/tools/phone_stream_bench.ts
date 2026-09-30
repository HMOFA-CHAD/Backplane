// Times the phone client (bridge.js) as agents stream: a kept state loaded
// (Backplane.save, e.g. from launch_bench.ts cold), a thread opened, then
// streamed-text frames ({"t":"delta"}) for another thread and for the open
// one, each handed over as the apps do (base64 CBOR, one call a frame).
//   BUN_JSC_useJIT=0 bun test/tools/phone_stream_bench.ts <bridge.js> <state file> <hub key> [frames]
import { readFileSync } from "fs";

const [bridge, file, key, nArg] = process.argv.slice(2);
const N = Number(nArg ?? 40);
(0, eval)(readFileSync(bridge, "utf8"));
const B = (globalThis as any).Backplane;
let screens = 0;
const handle = (text: string) => {
  const o = JSON.parse(text);
  if (o.screen) screens += 1;
};
// a CBOR map of text keys to text values
const cbor = (o: Record<string, string>) => {
  const out: number[] = [];
  const head = (maj: number, n: number) => {
    if (n < 24) out.push((maj << 5) | n);
    else if (n < 256) out.push((maj << 5) | 24, n);
    else out.push((maj << 5) | 25, n >> 8, n & 255);
  };
  const text = (s: string) => {
    const b = Buffer.from(s, "utf8");
    head(3, b.length);
    out.push(...b);
  };
  head(5, Object.keys(o).length);
  for (const [k, v] of Object.entries(o)) {
    text(k);
    text(v);
  }
  return Buffer.from(out).toString("base64");
};
handle(B.start("bench", "{}"));
handle(B.load(readFileSync(file, "utf8")));
handle(B.online(key, false, true));
const first = JSON.parse(B.hubs([key]));
const ids: string[] = [];
for (const p of first.screen.projects) for (const t of p.threads) ids.push(t.id);
handle(B.act("select", ids[0]));
const local = (id: string) => id.slice(id.indexOf("|") + 1);
const run = (label: string, thread: string) => {
  screens = 0;
  const t0 = performance.now();
  for (let i = 0; i < N; i++) handle(B.recv(key, cbor({ t: "delta", thread, text: "a few words " }), false, false));
  const ms = performance.now() - t0;
  console.log(`${label}: ${(ms / N).toFixed(1)} ms a frame, ${screens} screens for ${N} frames`);
};
run("another thread's tokens", local(ids[1]));
run("the open thread's tokens", local(ids[0]));
