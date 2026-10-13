// A stand-in for Google's agy_acp_server (Antigravity's ACP agent), for
// test/tools/agy_e2e.ts. It answers as 1.3.0 does (the replies in
// test/fixtures/antigravity), no model runs:
//   initialize       the real capabilities and auth methods
//   authenticate     gemini-api-key: {} (a missing key fails at session/new,
//                    as the real one does); oauth-*: with no token in
//                    $GEMINI_HOME/antigravity-acp/acp_token.json, it opens
//                    $BROWSER on a Google address whose redirect is a
//                    loopback port it listens on; the way back writes the
//                    token and answers {}
//   session/new      the fixture's models; session/resume answers no id
//   session/prompt   "ECHO: <text>" as a chunk, a tool call that completes,
//                    a permission request first when the text says "perm"
//                    and the mode is not yolo; then end_turn
// Every request goes to $AGY_LOG with what the environment held.
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const log = process.env.AGY_LOG ?? "/dev/null";
const home = process.env.GEMINI_HOME ?? "";
const acp = join(home, "antigravity-acp");
const token = join(acp, "acp_token.json");
const say = (o: object) => process.stdout.write(JSON.stringify({ jsonrpc: "2.0", ...o }) + "\n");
const note = (s: string) => appendFileSync(log, s + "\n");
const fixture = readFileSync(join(import.meta.dir, "../fixtures/antigravity/turn.jsonl"), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
const opened = fixture.find((o) => o.id === 2).result;
let method = "";
let mode = "default";
let sid = "";
let waiting: { id: number; perm: any } | null = null;
let pending: any = null;

note(`START home=${home} tmp=${process.env.TMPDIR ?? ""} harness=${process.env.ANTIGRAVITY_HARNESS_PATH ?? ""} gemkey=${process.env.GEMINI_API_KEY ?? ""} gkey=${process.env.GOOGLE_API_KEY ?? ""} args=${process.argv.slice(2).join(" ")}`);
note(`SETTINGS ${existsSync(join(acp, "settings.json")) ? readFileSync(join(acp, "settings.json"), "utf8").trim() : ""}`);

// as Python's webbrowser does with BROWSER: split, %s for the address
function browser(url: string) {
  const b = process.env.BROWSER ?? "";
  const parts = (b.match(/'[^']*'|\S+/g) ?? []).map((p) => (p.startsWith("'") ? p.slice(1, -1) : p)).map((p) => p.replace("%s", url));
  if (!parts.length) return;
  Bun.spawnSync(parts, { stdout: "inherit", stderr: "inherit" });
}

function google(id: number) {
  const state = "ST" + Math.random().toString(36).slice(2);
  const server = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    fetch(req) {
      const u = new URL(req.url);
      if (u.searchParams.get("state") !== state || !u.searchParams.get("code")) return new Response("bad", { status: 400 });
      mkdirSync(acp, { recursive: true });
      writeFileSync(token, JSON.stringify({ refresh_token: "r" }));
      note("SIGNED " + u.searchParams.get("code"));
      setTimeout(() => { server.stop(true); say({ id, result: {} }); }, 10);
      return new Response("signed in");
    },
  });
  const redirect = `http://127.0.0.1:${server.port}/`;
  note(`LISTEN ${server.port} ${state}`);
  browser(`https://accounts.google.com/o/oauth2/v2/auth?response_type=code&client_id=C&redirect_uri=${encodeURIComponent(redirect)}&scope=s&state=${state}&code_challenge=x&code_challenge_method=S256`);
}

function prompt(id: number, text: string) {
  const update = (u: object) => say({ method: "session/update", params: { sessionId: sid, update: u } });
  update({ sessionUpdate: "agent_message_chunk", content: { type: "text", text: "ECHO: " + text.slice(-40) } });
  update({ sessionUpdate: "tool_call", toolCallId: "T1", title: "Run ls", kind: "execute", status: "pending" });
  update({ sessionUpdate: "tool_call_update", toolCallId: "T1", status: "completed" });
  say({ id, result: { stopReason: "end_turn" } });
}

function handle(o: any) {
  note(`REQ ${o.method ?? "reply:" + o.id} ${JSON.stringify(o.params ?? o.result ?? {}).slice(0, 300)}`);
  if (!o.method) {
    // the answer to our permission request
    if (waiting && o.id === 900) { const w = waiting; waiting = null; note("PERMIT " + JSON.stringify(o.result)); prompt(w.id, w.perm); }
    return;
  }
  switch (o.method) {
    case "initialize":
      return say({ id: o.id, result: fixture.find((x) => x.id === 1).result });
    case "authenticate":
      method = o.params?.methodId ?? "";
      if (method.startsWith("oauth-") && !existsSync(token)) return google(o.id);
      return say({ id: o.id, result: {} });
    case "session/new":
    case "session/resume":
      if (method === "gemini-api-key" && !process.env.GEMINI_API_KEY)
        return say({ id: o.id, error: { code: -32000, message: "auth.type is set to 'gemini-api-key' in settings.json but the GEMINI_API_KEY environment variable is not set." } });
      sid = o.params?.sessionId ?? "S-" + Date.now();
      return say({ id: o.id, result: o.method === "session/new" ? { ...opened, sessionId: sid } : { modes: opened.modes, configOptions: opened.configOptions } });
    case "session/set_mode":
      mode = o.params?.modeId ?? "";
      note("MODE " + mode);
      return say({ id: o.id, result: {} });
    case "session/set_config_option":
      note("MODEL " + o.params?.value);
      if (!JSON.stringify(opened.configOptions).includes(`"${o.params?.value}"`)) return say({ id: o.id, error: { code: -32602, message: "unknown model" } });
      return say({ id: o.id, result: { configOptions: opened.configOptions } });
    case "session/prompt": {
      const text = (o.params?.prompt ?? []).map((b: any) => b.text ?? "").join("");
      note("PROMPT " + JSON.stringify(text.slice(0, 80)) + (text.includes("<backplane_instructions>") ? " +rules" : ""));
      if (text.includes("perm") && mode !== "yolo") {
        waiting = { id: o.id, perm: text };
        return say({ id: 900, method: "session/request_permission", params: { sessionId: sid, toolCall: { toolCallId: "T9", title: "Run rm -rf junk", kind: "execute", rawInput: { command: "rm -rf junk" } },
          options: [{ optionId: "a1", name: "Allow", kind: "allow_once" }, { optionId: "aa", name: "Always", kind: "allow_always" }, { optionId: "r1", name: "Deny", kind: "reject_once" }] } });
      }
      return prompt(o.id, text);
    }
    default:
      if (o.id !== undefined) say({ id: o.id, error: { code: -32601, message: "not supported" } });
  }
}

let buf = "";
process.stdin.on("data", (d) => {
  buf += d.toString();
  let i;
  while ((i = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, i);
    buf = buf.slice(i + 1);
    if (line.trim()) { try { handle(JSON.parse(line)); } catch (e) { note("BAD " + line); } }
  }
});
process.stdin.on("end", () => { note("EOF"); if (!pending) process.exit(0); });
