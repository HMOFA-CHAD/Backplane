// MCP calls as agents make them, against a running test hub: each tool
// below N times in turn, from one of the hub's threads, timed round trip,
// then the hub's own hub.mcp row (/debug/perf.json).
//
//   bun test/tools/mcp_load.ts PORT HOME [N]
// MCP_PROBE=NAME first asks for lock NAME and leaves it waiting (hold the
// flock on BACKPLANE_LOCK_DIR/bp-NAME.lock outside the hub meanwhile, so the
// hub probes it every 100 ms), then reports hub.lock_probe too.
//
// HOME is the test hub's home (token, events.jsonl). Never the live hub.
import { readFileSync } from "node:fs";
import { join } from "node:path";

const [portS, home, nS = "20"] = process.argv.slice(2);
const port = Number(portS);
if (!port || port === 3787) throw new Error("a test hub's port, never 3787");
const n = Number(nS);
const token = readFileSync(join(home, "token"), "utf8").trim();
const lines = readFileSync(join(home, "events.jsonl"), "utf8").split("\n").filter((l) => l.trim()).map((l) => { try { return JSON.parse(l); } catch { return {}; } });
const made = lines.filter((o) => o.$ === "ThreadCreated");
const me = made[made.length - 1].id; // the newest thread calls
const msgs = new Map<string, number>();
for (const o of lines) if (o.$ === "MessagePosted") msgs.set(o.thread, (msgs.get(o.thread) ?? 0) + 1);
const long = [...msgs.entries()].sort((a, b) => b[1] - a[1])[0][0];
let rid = 0;
const call = async (name: string, args: object) => {
  const t0 = performance.now();
  const r = await fetch(`http://127.0.0.1:${port}/mcp/${me}?token=${token}`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: ++rid, method: "tools/call", params: { name, arguments: args } }),
  });
  await r.text();
  return performance.now() - t0;
};
const tools: [string, () => object][] = [
  ["thread_list", () => ({})],
  ["thread_read", () => ({ thread: long, limit: 40 })],
  ["task_status", () => ({ task: "k-none" })],
  ["lock_list", () => ({})],
  ["work_list", () => ({})],
  ["wake_list", () => ({})],
  ["wake_on", () => ({ kind: "thread", target: long, events: ["end"], note: "load" })],
  ["lock_acquire", () => ({ name: "mcpload", note: "load" })],
  ["lock_release", () => ({ name: "mcpload" })],
];
const perf = async () => {
  const j = await (await fetch(`http://127.0.0.1:${port}/debug/perf.json?token=${token}`)).json();
  return (j.rows ?? []).find((r: any) => r.name === "hub.mcp");
};
const probe = process.env.MCP_PROBE ?? "";
if (probe) await call("lock_acquire", { name: probe, note: "probe" });
const before = await perf();
const beforeAll = await (await fetch(`http://127.0.0.1:${port}/debug/perf.json?token=${token}`)).json();
const pct = (xs: number[], p: number) => xs.slice().sort((a, b) => a - b)[Math.min(xs.length - 1, Math.floor(xs.length * p))];
const all: Record<string, number[]> = {};
for (let i = 0; i < n; i++) for (const [name, a] of tools) (all[name] ??= []).push(await call(name, a()));
const after = await perf();
console.log(`mcp_load: ${n} rounds from ${me}, thread_read on ${long}`);
for (const [name, xs] of Object.entries(all)) console.log(`  ${name.padEnd(14)} p50 ${pct(xs, 0.5).toFixed(1).padStart(7)} ms  p90 ${pct(xs, 0.9).toFixed(1).padStart(7)}  max ${Math.max(...xs).toFixed(1).padStart(7)}`);
if (probe) {
  const j = await (await fetch(`http://127.0.0.1:${port}/debug/perf.json?token=${token}`)).json();
  for (const name of ["hub.lock_probe", "hub.lock_saw"]) {
    const a = (j.rows ?? []).find((r: any) => r.name === name), b = (beforeAll.rows ?? []).find((r: any) => r.name === name);
    if (a) { const dn = a.n - (b?.n ?? 0), ds = a.sum - (b?.sum ?? 0); console.log(`  ${name}: ${dn} in the run, mean ${(ds / Math.max(dn, 1) / 1000).toFixed(2)} ms, max ${(a.max / 1000).toFixed(1)} ms`); }
  }
  await call("lock_cancel", { name: probe });
}
if (after) {
  const dn = Number(after.n ?? after.count ?? 0) - Number(before?.n ?? before?.count ?? 0);
  const ds = Number(after.sum ?? after.total ?? 0) - Number(before?.sum ?? before?.total ?? 0);
  console.log(`  hub.mcp: ${dn} calls, mean ${(ds / Math.max(dn, 1) / 1000).toFixed(2)} ms own+waits (row: ${JSON.stringify(after).slice(0, 160)})`);
}
