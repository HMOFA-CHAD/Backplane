// The phone bridge renders a streamed reply a settled paragraph at a time
// (bridge.js's liveNodes): for every prefix of real markdown (the repo's
// docs, streamed in uneven chunks as an agent's words arrive) its nodes must
// be exactly the nodes of the whole text rendered at once (App.live_nodes).
//   bun test/tools/phone_live_test.ts mobile/build/assets/bridge.js
import { readFileSync, readdirSync } from "node:fs";
import { strict as assert } from "node:assert";

const bridge = process.argv[2] ?? "mobile/build/assets/bridge.js";
(0, eval)(readFileSync(bridge, "utf8"));
const B = (globalThis as any).Backplane;
B.start("live-test", "{}");

let seed = 7;
const rnd = (n: number) => {
  seed = (seed * 1103515245 + 12345) & 0x7fffffff;
  return seed % n;
};
const texts: string[] = [];
for (const f of readdirSync("docs").filter((f) => f.endsWith(".md")).sort().slice(0, 12)) texts.push(readFileSync(`docs/${f}`, "utf8").slice(0, 6000));
// what a reply holds that docs may not: fences with blank lines, indented
// and nested lists, a table, quotes, a fence never closed, CRLF, tabs
texts.push("Intro line\n\n```js\nconst a = 1;\n\nconst b = 2;\n```\n\n- one\n\n  - nested\n- two\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n> quoted\n>\n> more\n\n    indented\n\n    code\n\nend http://x.y/z and `a/b` path/to/file.ts\n");
texts.push("para\r\n\r\n```\r\nopen\r\n\r\nstill open\n \t\n\nafter");
texts.push("# Title\n\n\n\nText with **bold** and _it_\n\n1. a\n2. b\n\n\t\nlast");
let n = 0;
for (const t of texts) {
  // a fresh reply (the bridge starts over when the text is not a growth)
  JSON.parse(B.liveHalves(""));
  for (let at = 0; at < t.length; ) {
    at = Math.min(t.length, at + 1 + rnd(40));
    const h = JSON.parse(B.liveHalves(t.slice(0, at)));
    assert.deepEqual(h.kept, h.whole, `differs at ${at} of a ${t.length}-char text: ${JSON.stringify(t.slice(Math.max(0, at - 60), at))}`);
    n++;
  }
}
// a text that is not the last one grown starts over
const a = JSON.parse(B.liveHalves("one\n\ntwo\n\nthree"));
assert.deepEqual(a.kept, a.whole);
const b = JSON.parse(B.liveHalves("other\n\nfour"));
assert.deepEqual(b.kept, b.whole);
console.log(`PASS: ${n} prefixes of ${texts.length} texts render the same a paragraph at a time as whole`);
