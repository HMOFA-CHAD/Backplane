// tap → content on a kept state: bun tap_bench.ts BRIDGE STATE KEY
import { readFileSync } from "fs";
const [bridge, file, key] = process.argv.slice(2);
(0, eval)(readFileSync(bridge, "utf8"));
const B = (globalThis as any).Backplane;
let screen: any = null;
const T = (label: string, f: () => string) => {
  const t0 = performance.now();
  const text = f();
  const t1 = performance.now();
  const o = JSON.parse(text);
  const t2 = performance.now();
  if (o.screen) screen = o.screen;
  const th = o.screen?.thread;
  console.log(`${label.padEnd(28)} bend ${(t1 - t0).toFixed(0).padStart(5)} ms  parse ${(t2 - t1).toFixed(0).padStart(4)} ms  ${(text.length / 1e3).toFixed(0).padStart(6)} KB  entries ${th?.entries?.length ?? "-"} plane ${o.screen?.plane ? "y" : "n"} bot ${o.screen?.bot?.kind ?? "-"}`);
};
T("start", () => B.start("bench", "{}"));
T("load", () => B.load(readFileSync(file, "utf8")));
T("offline", () => B.online(key, false, true));
T("hubs", () => B.hubs([key]));
T("list screen", () => B.screen());
const uber = screen.uber;
console.log("uber", JSON.stringify(uber)?.slice(0, 200));
console.log("bots", (screen.bots ?? []).map((b: any) => b.name + "=" + b.id + ":" + (b.act ?? "")).join(" "));
const bub = (screen.bots ?? []).find((b: any) => /Bub/.test(b.name));
const id = uber?.id ?? bub?.id;
const act = uber ? "uber" : bub?.act ?? "bot";
T(`tap ${act}`, () => B.act(act, id));
T("again", () => B.screen());
console.log("tabs", JSON.stringify(screen.bot?.tabs), "tab", screen.bot?.tab);
for (const tab of screen.bot?.tabs ?? []) {
  const v = tab.value ?? tab.id ?? tab;
  T(`tab ${JSON.stringify(v).slice(0, 20)}`, () => B.act(tab.act ?? "bot-tab", typeof v === "string" ? v : JSON.stringify(v)));
}
T("back (select '')", () => B.act("select", ""));
T("tap again", () => B.act(act, id));

// Every tappable bot and room must predict the exact native destination.
const nav = (s: any) => s.bot && s.bot.kind !== "bot" ? `@${s.bot.kind}:${s.bot.id}` : s.sel;
T("nav list", () => B.act("select", ""));
const rows = [
  ...(screen.uber ? [{ ...screen.uber, act: "uber" }] : []),
  ...(screen.bots ?? []),
  ...(screen.rooms ?? []).map((r: any) => ({ ...r, act: "room" })),
];
for (const row of rows) {
  console.log(`row ${row.name} nav=${row.nav}`);
  if (!row.nav) throw new Error(`missing nav for ${row.name}`);
  T(`open ${row.name}`, () => B.act(row.act ?? (row.remote ? "remote" : "bot"), row.id));
  if (nav(screen) !== row.nav) throw new Error(`${row.name}: row nav ${row.nav} != screen nav ${nav(screen)}`);
  T(`back ${row.name}`, () => B.act("select", ""));
}
console.log(`PASS: ${rows.length} row navs match opened screens`);
