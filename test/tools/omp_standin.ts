// A stand-in `omp` (Oh My Pi 18.12.6) for test/tools/pi_omp_e2e.ts. It runs
// no model. It answers `omp --version`, `omp models --json`, and
// `omp --mode rpc-ui [flags]` the way omp's RPC mode does (docs/rpc.md at
// 18.12.6; frames recorded from the real omp 18.12.6 on 2026-10-25): a
// ready frame, then responses, message_update deltas, tool_execution_*,
// message_end with usage, extension_ui_request dialogs, prompt_result and
// get_session_stats. It loads the extension Backplane passes with `-e` the
// way omp does (its default export called with a registerTool API), so
// Backplane's own tools are the real ones, called over the hub's MCP.
// Every command goes to OMP_LOG as "REQ <type> <json>"; the flags as ARGS;
// the dialog answers as UI lines; a Backplane tool's result as BP. A
// thread's session is a file in its --session-dir (--continue takes the
// newest up again).
//
// A prompt's text picks what the turn does: "perm please" (a bash approval,
// a select titled "Allow tool: bash"), "write please" (a write approval),
// "ask please" (an `ask` question as a select), "bp tool" (Backplane's
// thread_list through the extension), "slow" (waits 30 s, for Stop), or
// anything else (a bash call, then "ECHO: <text>").
import { appendFileSync, existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const argv = process.argv.slice(2);
const log = process.env.OMP_LOG ?? "/dev/null";
const say = (s: string) => appendFileSync(log, s + "\n");

if (argv[0] === "--version") { console.log("omp/18.12.6-standin"); process.exit(0); }
if (argv[0] === "models") {
  console.log(JSON.stringify({ models: [
    { provider: "standin", kind: "chat", id: "fake-omp", selector: "standin/fake-omp", name: "Fake OMP", reasoning: true, thinking: ["low", "high"], input: ["text"] },
    { provider: "standin", kind: "chat", id: "flat", selector: "standin/flat", name: "Flat", reasoning: false, thinking: null, input: ["text"] },
  ] }));
  process.exit(0);
}
const flag = (f: string) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : undefined; };
if (flag("--mode") !== "rpc-ui") { console.error("omp stand-in: only --version, models, --mode rpc-ui"); process.exit(2); }
say("ARGS " + JSON.stringify(argv));
say("ENV " + JSON.stringify({ mcp: process.env.BACKPLANE_OMP_MCP ?? "" }));

const out = (o: object) => process.stdout.write(JSON.stringify(o) + "\n");
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const yolo = flag("--approval-mode") === "yolo";

// the session: the newest file in the folder (--continue), else a new one
const dir = flag("--session-dir") ?? "/tmp/omp-standin-sessions";
mkdirSync(dir, { recursive: true });
const files = argv.includes("--continue") ? readdirSync(dir).filter((f) => f.endsWith(".json")).sort() : [];
const file = files.length ? join(dir, files.at(-1)!) : join(dir, `${Date.now()}_omp-${Math.floor(Math.random() * 1e6)}.json`);
const session = existsSync(file) ? JSON.parse(readFileSync(file, "utf8")) : { id: file.split("_").at(-1)!.replace(".json", ""), messages: 0, input: 0, output: 0, cost: 0 };
const save = () => writeFileSync(file, JSON.stringify(session));

// the extension's tools
const tools: any[] = [];
const ext = flag("-e");
if (ext) await (await import(ext)).default({ registerTool: (t: any) => tools.push(t), on: () => {} });
say("TOOLS " + tools.map((t) => t.name).join(","));

let ui = 0;
const waiting = new Map<string, (r: any) => void>();
const dialog = (o: object) => new Promise<any>((res) => { const id = "ui-" + ++ui; waiting.set(id, res); out({ type: "extension_ui_request", id, ...o }); });
const approve = async (tool: string, detail: string) => {
  if (yolo) return { value: "Approve" };
  const r = await dialog({ method: "select", title: `Allow tool: ${tool}\n${detail}`, options: ["Approve", `Approve ${tool} for this session`, "Deny"] });
  say("UI " + JSON.stringify(r));
  return r;
};
const call = (name: string, args: object) => {
  const id = "c" + Math.floor(Math.random() * 1e6);
  out({ type: "tool_execution_start", toolCallId: id, toolName: name, args });
  out({ type: "tool_execution_end", toolCallId: id, toolName: name, isError: false });
};

async function prompt(id: string, text: string) {
  if (text.includes("perm please")) {
    if ((await approve("bash", "Command: rm -rf junk")).value !== "Deny") call("bash", { command: "rm -rf junk" });
  } else if (text.includes("write please")) {
    if ((await approve("write", "Path: notes/a.txt")).value !== "Deny") call("write", { path: "notes/a.txt" });
  } else if (text.includes("ask please")) {
    say("UI " + JSON.stringify(await dialog({ method: "select", title: "Which colour?", options: ["Red", "Blue"] })));
  } else if (text.includes("bp tool")) {
    const t = tools.find((x) => x.name === "mcp__backplane__thread_list");
    const r = t ? await t.execute("c-bp", {}, undefined) : { content: [{ type: "text", text: "no such tool" }] };
    say("BP " + JSON.stringify(r).slice(0, 300));
    call("write", { path: "xd://mcp__backplane__thread_list" });
  } else if (text.includes("slow")) {
    await sleep(30000);
  } else {
    call("bash", { command: "ls notes" });
  }
  const reply = "ECHO: " + text.slice(0, 40);
  out({ type: "message_update", messageId: "m1", message: { role: "assistant" }, assistantMessageEvent: { type: "text_start", contentIndex: 0 } });
  out({ type: "message_update", messageId: "m1", message: { role: "assistant" }, assistantMessageEvent: { type: "text_delta", contentIndex: 0, delta: reply } });
  out({ type: "message_end", message: { role: "assistant", stopReason: "stop", usage: { input: 1000, output: 20, cacheRead: 0, cacheWrite: 0, totalTokens: 1020, cost: { total: 0.002 } } } });
  session.messages += 2; session.input += 1000; session.output += 20; session.cost += 0.002; save();
  out({ type: "prompt_result", id, agentInvoked: true, status: "completed", sessionSettled: true });
  out({ type: "session_settled" });
}

function handle(o: any) {
  if (o.type === "extension_ui_response") { const w = waiting.get(o.id); if (w) { waiting.delete(o.id); w(o); } return; }
  say("REQ " + o.type + " " + JSON.stringify(o));
  const reply = (data: object) => out({ id: o.id, type: "response", command: o.type, success: true, data });
  switch (o.type) {
    case "set_event_filter": return reply({ events: null, messageUpdates: o.messageUpdates ?? "full" });
    case "get_state": say(`STATE ${session.id} ${session.messages}`); return reply({ sessionId: session.id, messageCount: session.messages, systemPrompt: "x".repeat(2000) });
    case "prompt": reply({}); void prompt(o.id, String(o.message ?? "")); return;
    case "get_session_stats":
      return reply({ sessionId: session.id, tokens: { input: session.input, output: session.output, reasoning: 0, cacheRead: 0, cacheWrite: 0, total: session.input + session.output },
        cost: session.cost, contextUsage: { tokens: 1020, contextWindow: 200000, percent: 0.51 } });
    default: return out({ id: o.id, type: "response", command: o.type, success: false, error: `Unknown command: ${o.type}` });
  }
}

out({ type: "ready", protocolVersion: 1, supportedProtocolVersions: [1, 2], maxFrameBytes: 1048576, maxReassembledFrameBytes: 67108864 });
let buf = "";
process.stdin.on("data", (d) => {
  buf += d.toString();
  for (let i = buf.indexOf("\n"); i >= 0; i = buf.indexOf("\n")) {
    const line = buf.slice(0, i).replace(/\r$/, "");
    buf = buf.slice(i + 1);
    if (line.trim()) { try { handle(JSON.parse(line)); } catch (e) { say("BAD " + line.slice(0, 200)); } }
  }
});
process.stdin.on("end", () => process.exit(0));
