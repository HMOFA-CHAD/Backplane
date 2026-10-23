import Base
import ./json.bend as J
import ./acp.bend as AC
import ./dialog.bend as DL

# Pi (`pi --mode rpc`, earendil-works/pi 1.4)
# -------------------------------------------
# Pi speaks neither ACP nor MSP: its RPC mode reads JSON commands on stdin
# and writes responses and session events on stdout, one a line
# (docs/rpc.md, rpc-commands.md, json.md of @earendil-works/pi-coding-agent
# 1.4.0). One process per turn, on Grok's runner (msp.bend's PPi):
#   1 get_state: the session Pi opened (`--session-id`, made when absent);
#   2 prompt: the person's text; then its events until agent_settled.
# What it says is reported in the Codex event shapes (acp.bend), through
# the same AC.Acp state: sid the session, buf the reply so far, done, and
# seen the failure the last assistant message ended with ("" for none).
#
# Pi has no approval prompts of its own and no MCP flag. Backplane gives it
# both through an extension it writes (Pi.ext, loaded with `-e`): it adds
# the thread's Backplane MCP server and, before each tool the thread's mode
# does not allow, asks through Pi's extension UI (an extension_ui_request
# "confirm" titled Pi.approval.title()), which goes to the person as an
# approval (dialog.bend's envelope; the answer an extension_ui_response).
# Other extensions' dialogs go to the person as questions. Instructions go
# in with `--append-system-prompt` at every start, never into the
# conversation, so a resumed session does not repeat them.

def Pi.cmd(+id: String, +ty: String, kvs: List<&2, J.KV>) -> String:
  J.Json.show(J.Json.obj(J.KV{"id", J.Str{id}} <> J.KV{"type", J.Str{ty}} <> kvs))

# the first line of every turn
def Pi.init() -> String:
  Pi.cmd("1", "get_state", Nil{})

def Pi.text(t: AC.AcpTurn) -> String:
  match t:
    case AC.AcpTurn{_, _, _, x, _, _}:
      x

def Pi.prompt(+t: AC.AcpTurn) -> String:
  Pi.cmd("2", "prompt", [J.KV{"message", J.Str{Pi.text(t)}}])

# The session
# -----------
# A thread's session id is Backplane's, made at its first turn from the
# thread and the turn's gen (Pi takes letters, digits, ".", "_" and "-",
# first and last a letter or digit), and passed with `--session-id`, which
# opens that session in the thread's folder or makes it.

def Pi.safe.c(+c: U32) -> U32:
  Bool.pick(U32, Bool.or(Bool.or(Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)), Bool.and(U32.is_ge(c, 65), U32.is_le(c, 90))),
    Bool.or(Bool.and(U32.is_ge(c, 97), U32.is_le(c, 122)), Bool.or(Bool.and(U32.is_ge(c, 45), U32.is_le(c, 46)), U32.is_eq(c, 95)))), c, 45)

def Pi.safe(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{Chr{+c}, t}:
      SCon{Chr{Pi.safe.c(c)}, Pi.safe(t)}

# the session a turn opens: the thread's own, else a new one
def Pi.session(+session: String, +thread: String, +gen: String) -> String:
  Bool.pick(String, String.is_empty(session), "bp-" ++ Pi.safe(thread) ++ "-" ++ Pi.safe(gen) ++ "-0", session)

# The approval mode (the extension reads BACKPLANE_PI_MODE): supervised
# (0) asks before every tool but reading and Backplane's own; accept edits
# (1) also lets edit and write run; auto (2) and full access (3) ask
# nothing (Pi has no judgement of its own to defer to, as opencode)
def Pi.mode.k(i: Nat) -> String:
  match i:
    case 0n:
      "ask"
    case 1n:
      "edit"
    case _:
      "allow"

def Pi.approval.title() -> String:
  "backplane:approval"

# The extension, as Pi loads it (plain ES module JavaScript: jiti loads it
# as it is)
def Pi.ext() -> String:
  String.join([
    "// Written by Backplane for its Pi threads; rewritten before every turn.",
    "// The thread's Backplane MCP server, and an approval before each tool the",
    "// thread's mode does not allow (BACKPLANE_PI_MODE: ask, edit or allow).",
    "export default function (pi) {",
    "  const url = process.env.BACKPLANE_PI_MCP || '';",
    "  const mode = process.env.BACKPLANE_PI_MODE || 'ask';",
    "  if (url) pi.registerMcpServer('backplane', { url, exposure: 'direct', description: 'Backplane: this thread, its project, viewers and other threads' });",
    "  const reads = new Set(['read', 'grep', 'find', 'ls']);",
    "  const edits = new Set(['edit', 'write']);",
    "  pi.on('tool_call', async (event, ctx) => {",
    "    const name = String(event.toolName);",
    "    if (mode === 'allow' || reads.has(name) || name.startsWith('mcp__backplane__')) return;",
    "    if (mode === 'edit' && edits.has(name)) return;",
    "    const ok = await ctx.ui.confirm('" ++ Pi.approval.title() ++ "', JSON.stringify({ tool: name, input: event.input }), { signal: ctx.signal });",
    "    if (!ok) return { block: true, reason: 'The user declined this tool call.' };",
    "  });",
    "}",
    ""], "\n")

# State
# -----

def Pi.close(a: AC.Acp) -> AC.Acp:
  match a:
    case AC.Acp{s, b, _, k}:
      AC.Acp{s, b, True{}, k}

def Pi.with_sid(a: AC.Acp, +sid: String) -> AC.Acp:
  match a:
    case AC.Acp{_, b, d, k}:
      AC.Acp{sid, b, d, k}

def Pi.buf(a: AC.Acp) -> String:
  match a:
    case AC.Acp{_, b, _, _}:
      b

def Pi.add(a: AC.Acp, +x: String) -> AC.Acp:
  match a:
    case AC.Acp{s, b, d, k}:
      AC.Acp{s, b ++ x, d, k}

def Pi.err(a: AC.Acp) -> String:
  match a:
    case AC.Acp{_, _, _, k}:
      k

def Pi.set_err(a: AC.Acp, +e: String) -> AC.Acp:
  match a:
    case AC.Acp{s, b, d, _}:
      AC.Acp{s, b, d, e}

def Pi.none(a: AC.Acp) -> AC.AcpOut:
  AC.AcpOut{a, Nil{}, Nil{}, Nil{}}

# Failures
# --------

def Pi.signin(+low: String) -> Bool:
  Bool.or(Bool.or(String.contains(low, "no api key"), String.contains(low, "/login")), Bool.or(String.contains(low, "unauthorized"), String.contains(low, "no model")))

def Pi.hint.k(+low: String, +msg: String) -> String:
  Bool.pick(String, String.contains(low, "model not found"), msg ++ " (pick another Pi model in the composer)",
    Bool.pick(String, Pi.signin(low), msg ++ " (sign Pi in once: run `pi` and use /login, or set the provider's API key)", msg))

# the reason, and how to fix it when that is known
def Pi.hint(+msg: String) -> String:
  Pi.hint.k(String.to_lower(String.take(msg, 400n)), msg)

def Pi.fail(a: AC.Acp, +msg: String) -> AC.AcpOut:
  AC.AcpOut{Pi.close(a), Nil{}, [AC.Acp.failed(Pi.hint(msg))], Nil{}}

def Pi.notice(+msg: String) -> String:
  AC.Acp.event("notice", [J.KV{"message", J.Str{msg}}])

# Replies to our commands (by id)
# -------------------------------

# a resumed session with no messages is one Pi no longer had (it made the
# id afresh): the person is told once that the agent starts without the
# earlier conversation
def Pi.lost.msg(+sid: String) -> String:
  "Pi had no saved conversation for session " ++ sid ++ " in this folder, so this turn starts without the earlier context. This thread's history in Backplane is kept."

def Pi.lost(resumed: Bool, +count: String, +sid: String) -> List<&2, String>:
  Bool.pick(List<&2, String>, Bool.and(resumed, String.eq(count, "0")), [Pi.notice(Pi.lost.msg(sid))], Nil{})

def Pi.opened.k(a: AC.Acp, +t: AC.AcpTurn, +sid: String, +count: String) -> AC.AcpOut:
  AC.AcpOut{Pi.with_sid(a, sid), [Pi.prompt(t)],
    AC.Acp.event("thread.started", [J.KV{"thread_id", J.Str{sid}}]) <> Pi.lost(Bool.not(String.is_empty(AC.Acp.session(t))), count, sid), Nil{}}

# the session is open: note it, then the prompt
def Pi.opened(a: AC.Acp, +t: AC.AcpTurn, +d: J.Json) -> AC.AcpOut:
  Pi.opened.k(a, t, J.Json.get_str(d, "sessionId", AC.Acp.session(t)), J.Json.as_raw(J.Json.get(d, "messageCount"), "0"))

# a prompt an extension command handled starts no run: the turn is over
def Pi.handled(h: Bool, a: AC.Acp) -> AC.AcpOut:
  match h:
    case True{}:
      AC.Acp.finished(a)
    case False{}:
      Pi.none(a)

def Pi.reply.k(i: Nat, ok: Bool, a: AC.Acp, +t: AC.AcpTurn, +o: J.Json) -> AC.AcpOut:
  match i ok:
    case 1n True{}:
      Pi.opened(a, t, J.Json.get_obj(o, "data"))
    case 2n True{}:
      Pi.handled(String.eq(J.Json.get_str(J.Json.get_obj(o, "data"), "disposition", ""), "handled"), a)
    case _ False{}:
      Pi.fail(a, J.Json.get_str(o, "error", "pi refused the command"))
    case _ True{}:
      Pi.none(a)

# Events
# ------

# a reply's text: streamed as it comes; a text block after earlier text
# starts its own paragraph
def Pi.delta(a: AC.Acp, +x: String) -> AC.AcpOut:
  AC.AcpOut{Pi.add(a, x), Nil{}, [AC.Acp.event("item.delta", [J.KV{"text", J.Str{x}}])], Nil{}}

def Pi.para(first: Bool, a: AC.Acp) -> AC.AcpOut:
  match first:
    case True{}:
      Pi.none(a)
    case False{}:
      Pi.delta(a, "\n\n")

def Pi.update.k(i: Nat, +a: AC.Acp, +e: J.Json) -> AC.AcpOut:
  match i:
    case 0n:
      Pi.para(String.is_empty(Pi.buf(a)), a)
    case 1n:
      Pi.delta(a, J.Json.get_str(e, "delta", ""))
    case _:
      Pi.none(a)

# what a call works on, in a line: a file tool's path, a search's pattern
def Pi.what(+args: J.Json) -> String:
  AC.Acp.or(J.Json.get_str(args, "path", J.Json.get_str(args, "file_path", "")),
    AC.Acp.or(J.Json.get_str(args, "pattern", J.Json.get_str(args, "query", "")), J.Json.get_str(args, "url", "")))

def Pi.label.say(+name: String, +what: String) -> String:
  Bool.pick(String, String.is_empty(what), name, name ++ " " ++ what)

def Pi.label.k(i: Nat, +name: String, +args: J.Json) -> String:
  match i:
    case 0n:
      AC.Acp.or(J.Json.get_str(args, "command", ""), "bash")
    case 1n:
      "backplane " ++ String.drop(name, 16n)
    case _:
      Pi.label.say(name, Pi.what(args))

# a call's line: a shell's is its command; Backplane's own tools by name;
# others their name and what they work on
def Pi.label(+name: String, +args: J.Json) -> String:
  Pi.label.k(Bool.pick(Nat, String.eq(name, "bash"), 0n, Bool.pick(Nat, String.starts_with(name, "mcp__backplane__"), 1n, 2n)), name, args)

# a call is logged when it starts (Pi gives its input then), and its end
# told ("tool.done": the hub snapshots the design then)
def Pi.log(+o: J.Json) -> String:
  AC.Acp.event("item.completed", [J.KV{"item", J.Json.obj([J.KV{"type", J.Str{"command_execution"}}, J.KV{"id", J.Str{J.Json.get_str(o, "toolCallId", "")}},
    J.KV{"command", J.Str{Pi.label(J.Json.get_str(o, "toolName", "tool"), J.Json.get_obj(o, "args"))}}])}])

def Pi.done(+o: J.Json) -> String:
  AC.Acp.event("tool.done", [J.KV{"id", J.Str{J.Json.get_str(o, "toolCallId", "")}}])

# an assistant message ends: one that failed is kept as the turn's failure
# (Pi may still retry it), one that ended well clears it
def Pi.msg_end.k(asst: Bool, +why: String, +err: String, a: AC.Acp) -> AC.Acp:
  match asst:
    case True{}:
      Pi.set_err(a, Bool.pick(String, String.eq(why, "error"), AC.Acp.or(err, "the model's provider failed"),
        Bool.pick(String, String.eq(why, "aborted"), AC.Acp.or(err, "Pi aborted the turn"), "")))
    case False{}:
      a

def Pi.msg_end(+m: J.Json, a: AC.Acp) -> AC.Acp:
  Pi.msg_end.k(String.eq(J.Json.get_str(m, "role", ""), "assistant"), J.Json.get_str(m, "stopReason", ""), J.Json.get_str(m, "errorMessage", ""), a)

# Pi will do nothing more: the turn ends, failed when its last assistant
# message did
def Pi.settled.k(ok: Bool, +e: String, a: AC.Acp) -> AC.AcpOut:
  match ok:
    case True{}:
      AC.Acp.finished(a)
    case False{}:
      Pi.fail(a, e)

def Pi.settled.e(+e: String, a: AC.Acp) -> AC.AcpOut:
  Pi.settled.k(String.is_empty(e), e, a)

def Pi.settled(+a: AC.Acp, +aborted: Bool) -> AC.AcpOut:
  Pi.settled.e(Bool.pick(String, Bool.and(aborted, String.is_empty(Pi.err(a))), "Pi aborted the turn", Pi.err(a)), a)

# Dialogs
# -------
# Backplane's approval goes to the person as one; any other extension's
# select, confirm, input or editor goes as a question (a confirm's choices
# Yes and No); a warning or error notification as a notice.

def Pi.str1(x: J.Json) -> String:
  match x:
    case J.Str{s}:
      s
    case other:
      J.Json.show(other)

def Pi.strs(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      Pi.str1(x) <> Pi.strs(t)

def Pi.detail(+input: J.Json) -> String:
  AC.Acp.or(J.Json.get_str(input, "command", ""), AC.Acp.or(Pi.what(input), String.take(J.Json.show(input), 400n)))

def Pi.ask.k(id: J.Json, +m: J.Json) -> String:
  DL.Dlg.line(id, "approval", "pi", [J.KV{"tool", J.Str{J.Json.get_str(m, "tool", "tool")}},
    J.KV{"detail", J.Str{Pi.detail(J.Json.get_obj(m, "input"))}}])

def Pi.ask(+o: J.Json) -> String:
  Pi.ask.k(DL.Dlg.id(o), Maybe.default(&2, J.Json, J.Json.parse(J.Json.get_str(o, "message", "")), J.Null{}))

# in full access the extension asks nothing; if it does, allowed
def Pi.approval(ask: Bool, +a: AC.Acp, +o: J.Json) -> AC.AcpOut:
  match ask:
    case True{}:
      AC.AcpOut{a, Nil{}, Nil{}, [Pi.ask(o)]}
    case False{}:
      AC.AcpOut{a, [DL.Dlg.reply(Pi.ask(o), "accept")], Nil{}, Nil{}}

def Pi.question.text(+o: J.Json) -> String:
  Bool.pick(String, String.is_empty(J.Json.get_str(o, "message", "")), J.Json.get_str(o, "title", ""),
    J.Json.get_str(o, "title", "") ++ "\n\n" ++ J.Json.get_str(o, "message", ""))

def Pi.question.opts(+o: J.Json) -> String:
  Bool.pick(String, String.eq(J.Json.get_str(o, "method", ""), "confirm"), "Yes\nNo", String.join(Pi.strs(J.Json.elems(J.Json.get_obj(o, "options"))), "\n"))

def Pi.question(+o: J.Json) -> String:
  DL.Dlg.line(DL.Dlg.id(o), "question", "pi", [J.KV{"tool", J.Str{"Pi"}}, J.KV{"detail", J.Str{Pi.question.text(o)}},
    J.KV{"options", J.Str{Pi.question.opts(o)}}, J.KV{"bool", J.Flag{String.eq(J.Json.get_str(o, "method", ""), "confirm")}}])

def Pi.notify(warn: Bool, +o: J.Json) -> List<&2, String>:
  match warn:
    case True{}:
      [Pi.notice("Pi: " ++ J.Json.get_str(o, "message", ""))]
    case False{}:
      Nil{}

def Pi.ui.pos(+m: String, +title: String) -> Nat:
  Bool.pick(Nat, Bool.and(String.eq(m, "confirm"), String.eq(title, Pi.approval.title())), 0n,
    Bool.pick(Nat, String.eq(m, "notify"), 2n,
      Bool.pick(Nat, Bool.or(Bool.or(String.eq(m, "select"), String.eq(m, "confirm")), Bool.or(String.eq(m, "input"), String.eq(m, "editor"))), 1n, 3n)))

def Pi.ui.k(i: Nat, ask: Bool, +a: AC.Acp, +o: J.Json) -> AC.AcpOut:
  match i:
    case 0n:
      Pi.approval(ask, a, o)
    case 1n:
      AC.AcpOut{a, Nil{}, Nil{}, [Pi.question(o)]}
    case 2n:
      AC.AcpOut{a, Nil{}, Pi.notify(Bool.not(String.eq(J.Json.get_str(o, "notifyType", "info"), "info")), o), Nil{}}
    case _:
      Pi.none(a)

# The lines
# ---------

def Pi.retry(+o: J.Json) -> String:
  Pi.notice("Pi is retrying (attempt " ++ J.Json.as_raw(J.Json.get(o, "attempt"), "?") ++ " of " ++ J.Json.as_raw(J.Json.get(o, "maxAttempts"), "?") ++ "): " ++ J.Json.get_str(o, "errorMessage", ""))

def Pi.compacted(+o: J.Json) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.is_empty(J.Json.get_str(o, "errorMessage", "")), Nil{}, [Pi.notice("Pi could not compact the conversation: " ++ J.Json.get_str(o, "errorMessage", ""))])

def Pi.kind(+ty: String) -> Nat:
  AC.Acp.pos(["response", "message_update", "tool_execution_start", "tool_execution_end", "message_end", "agent_settled", "extension_ui_request",
    "auto_retry_start", "compaction_start", "compaction_end", "extension_error"], ty, 0n)

def Pi.line.k(i: Nat, +a: AC.Acp, +t: AC.AcpTurn, +o: J.Json) -> AC.AcpOut:
  match i:
    case 0n:
      Pi.reply.k(AC.Acp.pos(["0", "1", "2"], J.Json.get_str(o, "id", ""), 0n), J.Json.get_bool(o, "success", False{}), a, t, o)
    case 1n:
      Pi.update.k(AC.Acp.pos(["text_start", "text_delta"], J.Json.get_str(J.Json.get_obj(o, "assistantMessageEvent"), "type", ""), 0n), a, J.Json.get_obj(o, "assistantMessageEvent"))
    case 2n:
      AC.AcpOut{a, Nil{}, [Pi.log(o)], Nil{}}
    case 3n:
      AC.AcpOut{a, Nil{}, [Pi.done(o)], Nil{}}
    case 4n:
      Pi.none(Pi.msg_end(J.Json.get_obj(o, "message"), a))
    case 5n:
      Pi.settled(a, J.Json.get_bool(o, "aborted", False{}))
    case 6n:
      Pi.ui.k(Pi.ui.pos(J.Json.get_str(o, "method", ""), J.Json.get_str(o, "title", "")), AC.Acp.ask_of(t), a, o)
    case 7n:
      AC.AcpOut{a, Nil{}, [Pi.retry(o)], Nil{}}
    case 8n:
      AC.AcpOut{a, Nil{}, [Pi.notice("Pi is compacting the conversation (" ++ J.Json.get_str(o, "reason", "") ++ ")")], Nil{}}
    case 9n:
      AC.AcpOut{a, Nil{}, Pi.compacted(o), Nil{}}
    case 10n:
      AC.AcpOut{a, Nil{}, [Pi.notice("A Pi extension failed (" ++ J.Json.get_str(o, "event", "") ++ "): " ++ J.Json.get_str(o, "error", ""))], Nil{}}
    case _:
      Pi.none(a)

def Pi.line.parsed(m: Maybe<&2, J.Json>, +a: AC.Acp, +t: AC.AcpTurn) -> AC.AcpOut:
  match m:
    case Some{+o}:
      Pi.line.k(Pi.kind(J.Json.get_str(o, "type", "")), a, t, o)
    case None{}:
      Pi.none(a)

# lines this turn reads nothing from, told by their start (Pi writes
# "type" first, and a message's "role" first): the system prompt and the
# whole conversation come again in some of them, so they are not parsed
def Pi.skip(+line: String) -> Bool:
  Bool.or(Bool.or(String.starts_with(line, "{\"type\":\"message_start\""), String.starts_with(line, "{\"type\":\"agent_end\"")),
    Bool.or(Bool.or(String.starts_with(line, "{\"type\":\"turn_end\""), String.starts_with(line, "{\"type\":\"message_end\",\"message\":{\"role\":\"system\"")),
      Bool.or(String.starts_with(line, "{\"type\":\"message_end\",\"message\":{\"role\":\"user\""), String.starts_with(line, "{\"type\":\"message_end\",\"message\":{\"role\":\"toolResult\""))))

def Pi.line.s(skip: Bool, +a: AC.Acp, +t: AC.AcpTurn, line: String) -> AC.AcpOut:
  match skip:
    case True{}:
      Pi.none(a)
    case False{}:
      Pi.line.parsed(J.Json.parse(line), a, t)

# one line from Pi
def Pi.line(+a: AC.Acp, +t: AC.AcpTurn, +line: String) -> AC.AcpOut:
  Pi.line.s(Pi.skip(line), a, t, line)
