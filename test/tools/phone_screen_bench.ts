// Times the phone client's screens with no hub: a kept state (Backplane.save,
// e.g. from launch_bench.ts cold) loaded, then the list's screen, each of a
// few threads opened and its screen again, and keys typed into a draft.
//   BUN_JSC_useJIT=0 bun test/tools/phone_screen_bench.ts <bridge.js> <state file> <hub key> [threads]
// Run with BUN_JSC_useJIT=0 for phone-like numbers (the apps' engines have
// no JIT); compare builds with each other.
import { readFileSync } from "fs";

const [bridge, file, key, nArg] = process.argv.slice(2);
(0, eval)(readFileSync(bridge, "utf8"));
const B = (globalThis as any).Backplane;
let screen: any = null;
const handle = (text: string) => {
  const o = JSON.parse(text);
  if (o.screen) screen = o.screen;
};
const time = (f: () => string) => {
  const t0 = performance.now();
  handle(f());
  return performance.now() - t0;
};
const stats = (xs: number[]) => {
  xs.sort((a, b) => a - b);
  const mean = xs.reduce((a, b) => a + b, 0) / xs.length;
  return `mean ${mean.toFixed(1)} ms  p50 ${xs[xs.length >> 1].toFixed(1)}  max ${xs[xs.length - 1].toFixed(1)}  (n ${xs.length})`;
};
handle(B.start("bench", "{}"));
console.log(`load: ${time(() => B.load(readFileSync(file, "utf8"))).toFixed(0)} ms`);
handle(B.online(key, false, true));
handle(B.hubs([key]));
const list: number[] = [];
for (let i = 0; i < 10; i++) list.push(time(() => B.screen()));
console.log("screen of the list: " + stats(list));
const ids: string[] = [];
for (const p of screen?.projects ?? []) for (const t of p.threads ?? []) ids.push(t.id);
const pick = ids.slice(0, Number(nArg ?? 6));
const opens: number[] = [];
const again: number[] = [];
for (const id of pick) {
  opens.push(time(() => B.act("select", id)));
  again.push(time(() => B.screen()));
}
console.log("open a thread: " + stats(opens));
console.log("screen of an open thread: " + stats(again));
const keys: number[] = [];
let draft = "";
for (const ch of "the quick brown fox") {
  draft += ch;
  keys.push(time(() => B.quiet("draft", draft)));
}
console.log("type a key (quiet): " + stats(keys));
handle(B.quiet("draft", ""));
