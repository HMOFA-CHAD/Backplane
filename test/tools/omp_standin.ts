// A stand-in `omp` (Oh My Pi 18.12.6) for test/tools/pi_omp_e2e.ts. It runs
// no model. It answers `omp --version`, `omp models --json`, and
// `omp acp [flags]` the way omp's ACP server does (src/modes/acp/acp-agent.ts,
// acp-client-bridge.ts, tools/approval.ts at 18.12.6). Every request goes to
// OMP_LOG as "REQ <method> <params>". The client's answers go there as
// PERMIT, ELICIT and AUTO lines. Sessions persist in OMP_STATE so a later
// process can resume them.
//
// A prompt's text picks what the turn does: "perm please" (bash through
// session/request_permission), "write please" (a write approval through
// form elicitation), "bp tool" (an approval for a Backplane MCP tool),
// "ask please" (an `ask` question), "slow" (waits 30 s, for Stop), or
// anything else (a tool call, then "ECHO: <text>").
import { appendFileSync, existsSync, readFileSync, writeFileSync } from "node:fs";

const argv = process.argv.slice(2);
const log = process.env.OMP_LOG ?? "/dev/null";
const state = process.env.OMP_STATE ?? "/tmp/omp-standin-sessions";
const say = (s: string) => appendFileSync(log, s + "\n");

if (argv[0] === "--version") { console.log("omp 18.12.6-standin"); process.exit(0); }
if (argv[0] === "models") {
  console.log(JSON.stringify({ models: [
    { provider: "standin", kind: "chat", id: "fake-omp", selector: "standin/fake-omp", name: "Fake OMP", reasoning: true, thinking: ["low", "high"], input: ["text"] },
    { provider: "standin", kind: "chat", id: "flat", selector: "standin/flat", name: "Flat", reasoning: false, thinking: null, input: ["text"] },
  ] }));
  process.exit(0);
}
if (argv[0] !== "acp") { console.error("omp stand-in: only --version, models, acp"); process.exit(2); }
say("ARGS " + JSON.stringify(argv));

const sessions = (): string[] => (existsSync(state) ? readFileSync(state, "utf8").split("\n").filter(Boolean) : []);
const out = (o: object) => process.stdout.write(JSON.stringify(o) + "\n");
const update = (sessionId: string, u: object) => out({ jsonrpc: "2.0", method: "session/update", params: { sessionId, update: u } });
let next = 100;
const waiting = new Map<number, (r: any) => void>();
const ask = (method: string, params: object) => new Promise<any>((res) => { const id = next++; waiting.set(id, res); out({ jsonrpc: "2.0", id, method, params }); });
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function prompt(id: number, p: any) {
  const sid = p.sessionId;
  const text = (p.prompt ?? []).map((b: any) => b.text ?? "").join("\n");
  if (text.includes("perm please")) {
    update(sid, { sessionUpdate: "tool_call", toolCallId: "c-perm", title: "rm -rf junk", kind: "execute", status: "pending", rawInput: { command: "rm -rf junk" } });
    const r = await ask("session/request_permission", { sessionId: sid, toolCall: { toolCallId: "c-perm", title: "rm -rf junk", kind: "execute", status: "pending", rawInput: { command: "rm -rf junk" } },
      options: [{ optionId: "allow_once", name: "Allow once", kind: "allow_once" }, { optionId: "allow_always", name: "Always allow", kind: "allow_always" },
        { optionId: "reject_once", name: "Reject", kind: "reject_once" }, { optionId: "reject_always", name: "Always reject", kind: "reject_always" }] });
    say("PERMIT " + JSON.stringify(r.result ?? r.error));
    update(sid, { sessionUpdate: "tool_call_update", toolCallId: "c-perm", status: "completed" });
  } else if (text.includes("write please") || text.includes("bp tool")) {
    const tool = text.includes("bp tool") ? "mcp__backplane__thread_list" : "write";
    const r = await ask("elicitation/create", { mode: "form", sessionId: sid, message: `Allow tool: ${tool}\nPath: notes/a.txt`,
      requestedSchema: { type: "object", properties: { value: { type: "string", enum: ["Approve", `Approve ${tool} for this session`, "Deny"] } }, required: ["value"] } });
    say((text.includes("bp tool") ? "AUTO " : "ELICIT ") + JSON.stringify(r.result ?? r.error));
  } else if (text.includes("ask please")) {
    const r = await ask("elicitation/create", { mode: "form", sessionId: sid, message: "Questions",
      requestedSchema: { type: "object", properties: { q0: { type: "string", title: "Which colour?", anyOf: [{ const: "Red", title: "Red" }, { const: "Blue", title: "Blue" }] } }, required: ["q0"] } });
    say("ELICIT " + JSON.stringify(r.result ?? r.error));
  } else if (text.includes("slow")) {
    await sleep(30000);
  } else {
    update(sid, { sessionUpdate: "tool_call", toolCallId: "c1", title: "Read notes/a.txt", kind: "read", status: "pending", rawInput: { path: "notes/a.txt" } });
    update(sid, { sessionUpdate: "tool_call_update", toolCallId: "c1", status: "completed" });
  }
  update(sid, { sessionUpdate: "agent_message_chunk", content: { type: "text", text: "ECHO: " + text.slice(0, 40) } });
  out({ jsonrpc: "2.0", id, result: { stopReason: "end_turn" } });
}

function handle(o: any) {
  if (o.method === undefined) { const w = waiting.get(o.id); if (w) { waiting.delete(o.id); w(o); } return; }
  say("REQ " + o.method + " " + JSON.stringify(o.params ?? {}));
  const reply = (result: object) => out({ jsonrpc: "2.0", id: o.id, result });
  const fail = (message: string) => out({ jsonrpc: "2.0", id: o.id, error: { code: -32603, message } });
  switch (o.method) {
    case "initialize":
      return reply({ protocolVersion: 1, agentInfo: { name: "omp", title: "omp", version: "18.12.6" }, authMethods: [{ id: "agent", name: "Use existing local credentials" }],
        agentCapabilities: { loadSession: true, mcpCapabilities: { http: true, sse: true }, promptCapabilities: { embeddedContext: true, image: true }, sessionCapabilities: { list: {}, fork: {}, resume: {}, close: {} } } });
    case "session/new": {
      const sid = "omp-" + Date.now() + "-" + Math.floor(Math.random() * 1e6);
      writeFileSync(state, sessions().concat([sid]).join("\n") + "\n");
      return reply({ sessionId: sid, configOptions: [], modes: { currentModeId: "default", availableModes: [] } });
    }
    case "session/resume":
      if (!sessions().includes(o.params.sessionId)) return fail(`ACP session not found: ${o.params.sessionId}`);
      return reply({ configOptions: [], modes: { currentModeId: "default", availableModes: [] } });
    case "session/set_config_option":
      if (o.params.configId === "model" && !String(o.params.value).startsWith("standin/")) return fail(`Unknown ACP model: ${o.params.value}`);
      return reply({ configOptions: [] });
    case "session/prompt":
      void prompt(o.id, o.params);
      return;
    case "session/cancel":
      return;
    default:
      return fail(`Method not found: ${o.method}`);
  }
}

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
