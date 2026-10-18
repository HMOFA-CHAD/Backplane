// Real isolated hub and real provider adapters, deterministic fake CLIs.
// No copied user state, credentials, push registrations or real model calls.
import { appendFileSync, chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { createInterface } from "node:readline";
const delay = (ms: number) => new Promise(r => setTimeout(r, ms));
const args = process.argv.slice(3);
const emit = (o: object) => console.log(JSON.stringify(o));
const log = (o: object) => appendFileSync(process.env.FALLBACK_AGENT_LOG!, JSON.stringify(o) + "\n");
if (process.argv[2] === "--claude") {
  if (args.includes("--version")) { console.log("2.1.286"); process.exit(0); }
  let chain = Promise.resolve();
  createInterface({ input: process.stdin }).on("line", line => {
    const o = JSON.parse(line);
    if (o.type === "control_request") {
      if (o.request?.subtype === "initialize") emit({ type: "control_response", response: { response: { models: [{ value: "sonnet", displayName: "Sonnet" }] } } });
      return;
    }
    if (o.type !== "user") return;
    const text = typeof o.message?.content === "string" ? o.message.content : (o.message?.content ?? []).map((b: any) => b.text ?? "").join("\n");
    chain = chain.then(async () => {
      log({ provider: "claude", prompt: text, pid: process.pid, args });
      emit({ type: "system", subtype: "init", session_id: "fake-claude", claude_code_version: "2.1.286", capabilities: ["msg_lifecycle_v1"] });
      emit({ type: "command_lifecycle", command_uuid: o.uuid, state: "queued" });
      emit({ type: "command_lifecycle", command_uuid: o.uuid, state: "started" });
      // One actual effect before the provider limit, with a recorded tool result.
      if (!existsSync(process.env.FALLBACK_EFFECT!)) {
        writeFileSync(process.env.FALLBACK_EFFECT!, "created-once\n");
        log({ effect: "created-once" });
        emit({ type: "assistant", uuid: "tool", parent_tool_use_id: null, message: { id: "tool", role: "assistant", content: [{ type: "tool_use", id: "create-once", name: "Bash", input: { command: "Created file once" } }] } });
        emit({ type: "user", message: { content: [{ type: "tool_result", tool_use_id: "create-once", content: "Created file once" }] } });
      }
      const reset = Math.floor(Date.now() / 1000) + 3600;
      emit({ type: "rate_limit_event", rate_limit_info: { status: "rejected", rateLimitType: "seven_day", resetsAt: reset } });
      emit({ type: "result", subtype: "error_during_execution", is_error: true, errors: ["Weekly limit reached"], resets_at: reset, session_id: "fake-claude" });
      emit({ type: "command_lifecycle", command_uuid: o.uuid, state: "failed" });
    });
  });
} else if (process.argv[2] === "--codex") {
  if (args.includes("--version")) { console.log("codex-cli 0.100.0"); process.exit(0); }
  const model = args[args.indexOf("-m") + 1] ?? "default";
  const prompt = args.at(-1)!;
  const session = `fake-${model}-${process.pid}`;
  log({ provider: "codex", model, prompt, args, pid: process.pid, resumed: args.includes("resume") });
  emit({ type: "thread.started", thread_id: session });
  if (model === "gpt-6.1-sol" || prompt.includes("EXHAUST_CHAIN")) {
    emit({ type: "turn.failed", error: { code: "quota_exceeded", scope: "model", message: "model quota exhausted", resets_at: Math.floor(Date.now() / 1000) + 3600 } });
  } else {
    emit({ type: "item.completed", item: { id: `answer-${process.pid}`, type: "agent_message", text: "Finished existing work; file already present." } });
    emit({ type: "turn.completed", usage: { input_tokens: 10, output_tokens: 5 } });
  }
} else {
  const bin = resolve(process.argv[2] ?? "build/fallback-app");
  const wire = resolve(process.argv[3] ?? "build/fallback-wire");
  const web = resolve(process.argv[4] ?? "build/fallback-web");
  for (const f of readdirSync(wire).filter(f => f.endsWith(".js"))) (0, eval)(readFileSync(join(wire, f), "utf8"));
  const W = (globalThis as any).Wire;
  const root = mkdtempSync(join(tmpdir(), "bp-fallback-e2e-"));
  const home = join(root, "home"), fake = join(root, "bin"), proj = join(root, "project");
  for (const p of [home, fake, proj, join(root, ".codex")]) mkdirSync(p);
  const quote = (s: string) => "'" + s.replaceAll("'", "'\\''") + "'";
  for (const provider of ["claude", "codex"]) {
    writeFileSync(join(fake, provider), `#!/bin/sh\nexec ${quote(process.execPath)} ${quote(resolve(import.meta.path))} --${provider} "$@"\n`); chmodSync(join(fake, provider), 0o755);
  }
  for (const p of ["grok", "muse", "agy", "gh", "tailscale", "kicad-cli", "freecad"]) { writeFileSync(join(fake, p), "#!/bin/sh\nexit 1\n"); chmodSync(join(fake, p), 0o755); }
  writeFileSync(join(root, ".codex/models_cache.json"), JSON.stringify({ models: [{ slug: "gpt-6.1-sol" }, { slug: "test-next" }] }));
  const event = ($: string, fields: object) => ({ $, ...fields, at: 1 });
  const thread = (id: string) => event("ThreadCreated", { id, project: "p", title: id, env: "local", branch: "", worktree: proj, provider: "claude", model: "sonnet" });
  const eventsPath = join(home, "events.jsonl"), agentLog = join(root, "agents.jsonl"), effect = join(root, "effect");
  writeFileSync(agentLog, "");
  writeFileSync(eventsPath, [event("ProjectCreated", { id: "p", title: "Fallback test", root: proj }), thread("worker"), thread("bot"), thread("child"),
    event("BotSet", { id: "b", name: "Bot", thread: "bot", look: 0, persona: "" }),
    event("ThreadLaunched", { id: "child", by: "worker", report: false }),
    event("SettingSet", { key: "fallback.chain", value: "claude/sonnet,codex/gpt-6.1-sol,codex/test-next" }),
    event("SettingSet", { key: "fallback.on", value: "on" }), event("SettingSet", { key: "restart.continue", value: "off" }),
    event("SettingSet", { key: "text.provider", value: "codex" }), event("SettingSet", { key: "text.model", value: "test-next" })].map(JSON.stringify).join("\n") + "\n");
  const listener = Bun.listen({ hostname: "127.0.0.1", port: 0, socket: { data() {} } });
  const port = listener.port; listener.stop(true);
  const env = { ...process.env, HOME: root, PATH: `${fake}:${process.env.PATH}`, DISPLAY: "", WAYLAND_DISPLAY: "", BACKPLANE_NO_UPDATE: "1", BACKPLANE_KEYRING_LOCKED: "0", BACKPLANE_PEERS: "", BACKPLANE_GOOGLE_BAKE: "0", FALLBACK_AGENT_LOG: agentLog, FALLBACK_EFFECT: effect, BACKPLANE_LOCK_DIR: join(root, "locks"), BACKPLANE_DEPLOY_LOCKS: join(root, "deploy-locks") };
  let proc: ReturnType<typeof Bun.spawn> | undefined, ws: WebSocket | undefined;
  let request = 0;
  const events = () => readFileSync(eventsPath, "utf8").trim().split("\n").filter(Boolean).map(x => JSON.parse(x));
  const launches = () => readFileSync(agentLog, "utf8").trim().split("\n").filter(Boolean).map(x => JSON.parse(x));
  const until = async (label: string, predicate: () => boolean, ms = 30000) => {
    const end = Date.now() + ms;
    while (Date.now() < end) { if (predicate()) return; await delay(50); }
    throw new Error(`timeout: ${label}`);
  };
  const check = (ok: unknown, label: string) => { if (!ok) throw new Error(label); console.log(`ok ${label}`); };
  const send = (m: string, p: object) => ws!.send(W.encode(JSON.stringify({ id: ++request, m, p })));
  const launch = async () => {
    proc = Bun.spawn([bin, "--headless", "--foreground", "--home", home, "--port", String(port), "--web", web, "--no-tailscale"], { env, stdout: Bun.file(join(root, "stdout")), stderr: Bun.file(join(root, "stderr")) });
    await until("hub ready", () => existsSync(join(home, "hub.lock")));
    let ready = false;
    for (let i = 0; i < 200; i++) { try { ready = (await fetch(`http://127.0.0.1:${port}/hello`)).ok; } catch {} if (ready) break; await delay(50); }
    check(ready, "isolated hub ready");
    ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
    await new Promise((resolve, reject) => { ws!.onopen = resolve; ws!.onerror = reject; });
  };
  const stop = async () => { ws?.close(); if (proc?.exitCode === null) proc.kill("SIGTERM"); await proc?.exited; };
  try {
    await launch();
    send("turn.start", { thread: "worker", text: "CREATE_ONCE and finish the work", msg: "original-request" });
    await until("primary->sol->next complete", () => events().some(e => e.$ === "TurnChanged" && e.thread === "worker" && e.state === "completed"));
    const first = launches();
    check(first.filter(l => l.effect).length === 1 && readFileSync(effect, "utf8") === "created-once\n", "one tool side effect across both fallbacks");
    const sol = first.find(l => l.model === "gpt-6.1-sol"), next = first.find(l => l.model === "test-next" && l.prompt.includes("CREATE_ONCE"));
    check(sol && next, "primary limit -> exact gpt-6.1-sol -> configured next step");
    check(!sol.resumed && !next.resumed, "fresh model-specific sessions");
    check(next.prompt.includes("Created file once") && next.prompt.includes("Do not repeat completed tool actions"), "handoff retains results and continuation instruction");
    check(events().filter(e => e.$ === "ActivityLogged" && e.thread === "worker" && e.kind === "fallback").length === 2, "per-thread durable switch audit");
    const alertCount = () => events().filter(e => e.$ === "SettingSet" && e.key.startsWith("alert.") && e.value.startsWith("fallback\t")).length;
    check(alertCount() === 2, "one persistent notification per distinct outage");
    const claudeStarts = first.filter(l => l.provider === "claude").length;
    for (const th of ["bot", "child"]) send("turn.start", { thread: th, text: "BOT_PING", msg: `prompt-${th}` });
    await until("bot and child complete", () => ["bot", "child"].every(th => events().some(e => e.$ === "TurnChanged" && e.thread === th && e.state === "completed")));
    check(launches().filter(l => l.provider === "claude").length === claudeStarts, "cached provider outage prevents bot/delegate relaunches");
    check(alertCount() === 2, "bot/delegate switches do not produce alert storm");
    await stop(); await launch();
    send("turn.start", { thread: "child", text: "AFTER_RESTART", msg: "after-restart" });
    await until("restart resumed chosen provider", () => launches().some(l => l.prompt?.includes("AFTER_RESTART")));
    check(launches().filter(l => l.provider === "claude").length === claudeStarts, "outage cache and selected fallback survive restart");
    send("turn.start", { thread: "worker", text: "EXHAUST_CHAIN", msg: "exhaust" });
    await until("exhaustion notification", () => events().some(e => e.$ === "SettingSet" && e.key.startsWith("alert.") && e.value.startsWith("fallback-blocked\t")));
    check(events().filter(e => e.$ === "MessagePosted" && e.msg === "original-request").length === 1, "original user prompt identity retained");
    check(!events().some(e => e.$ === "TaskFinished" && e.thread === "child" && e.state === "failed"), "no premature delegated-task failure");
    writeFileSync(join(root, "result.json"), JSON.stringify({ passed: true, port, home, events: eventsPath, agents: agentLog }, null, 2));
    console.log(`artifacts ${root}`);
    if (process.env.FALLBACK_ARTIFACTS) writeFileSync(process.env.FALLBACK_ARTIFACTS, root + "\n");
  } finally { await stop(); console.log(`artifacts ${root}`); }
}
