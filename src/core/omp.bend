import Base
import ./json.bend as J
import ./acp.bend as AC
import ./dialog.bend as DL

# Oh My Pi (`omp acp`, can1357/oh-my-pi 18.12)
# --------------------------------------------
# omp is not Pi (pi.bend): a fork with its own ACP server, so it runs on
# Grok's runner with Grok's translator (acp.bend) for what is the same:
# session/update (text, tool calls, plans, a call's end) and
# session/request_permission (bash, delete and move, options allow_once,
# allow_always, reject_once, reject_always). What it does its own way:
# - a thread's session is taken up again with session/resume (no replay);
#   one omp no longer has ("ACP session not found") opens afresh (7) and
#   the person is told once (a notice);
# - the model and the thinking level are the session's config options
#   (session/set_config_option "model" provider/id, then "thinking"), set
#   after the session opens: 4 and 5;
# - every other tool its approval mode asks for (write, plain edits,
#   eval, MCP tools...) it asks through a form elicitation, which a client
#   that offers none never sees: omp then refuses the tool. Backplane
#   offers forms: an approval ("Allow tool: <name>", choices Approve...
#   Deny) goes to the person as one, Backplane's own tools are allowed at
#   once (the hub has its own rules for them), and omp's `ask` questions
#   (one question; several at once are declined, said) go to the person
#   as questions (dialog.bend's envelope);
# - Backplane's instructions go in with `--append-system-prompt` at every
#   start, so the prompt is the person's text only;
# - a failure says how to fix omp.
# Request ids: 1 initialize, 2 session/new or session/resume, 7
# session/new after a lost session, 4 the model, 5 the thinking level,
# 3 the prompt.

# the turn: Grok's (cwd, MCP endpoint, text, session, whether tools ask)
# with the thread's model ("provider/id", "" for omp's default) and
# thinking level ("" for omp's default)
type OmpTurn is Data:
  OmpTurn{acp: AC.AcpTurn, model: String, effort: String}

def Omp.acp(t: OmpTurn) -> AC.AcpTurn:
  match t:
    case OmpTurn{a, _, _}:
      a

def Omp.model(t: OmpTurn) -> String:
  match t:
    case OmpTurn{_, m, _}:
      m

def Omp.effort(t: OmpTurn) -> String:
  match t:
    case OmpTurn{_, _, e}:
      e

def Omp.session(+t: OmpTurn) -> String:
  AC.Acp.session(Omp.acp(t))


def Omp.text(t: AC.AcpTurn) -> String:
  match t:
    case AC.AcpTurn{_, _, _, x, _, _}:
      x

# the approval mode (`--approval-mode`): supervised (0) asks before writes
# and commands (always-ask: only reading runs unasked), accept edits (1)
# lets writes and edits run (write), auto (2) and full access (3) ask
# nothing (yolo)
def Omp.mode.k(i: Nat) -> String:
  match i:
    case 0n:
      "always-ask"
    case 1n:
      "write"
    case _:
      "yolo"

# the first line: Grok's, offering form elicitation
def Omp.init() -> String:
  AC.Acp.rpc(1n, "initialize", J.Json.obj([J.KV{"protocolVersion", J.Num{"1"}},
    J.KV{"clientCapabilities", J.Json.obj([J.KV{"fs", J.Json.obj([J.KV{"readTextFile", J.Flag{False{}}}, J.KV{"writeTextFile", J.Flag{False{}}}])},
      J.KV{"terminal", J.Flag{False{}}}, J.KV{"elicitation", J.Json.obj([J.KV{"form", J.Json.obj(Nil{})}])}])}]))

def Omp.new.rpc(+id: Nat, +cwd: String, +mcp: String) -> String:
  AC.Acp.rpc(id, "session/new", J.Json.obj([J.KV{"cwd", J.Str{cwd}}, J.KV{"mcpServers", AC.Acp.mcp(mcp)}]))

def Omp.open.k(fresh: Bool, t: AC.AcpTurn) -> String:
  match fresh t:
    case True{} AC.AcpTurn{cwd, mcp, _, _, _, _}:
      Omp.new.rpc(2n, cwd, mcp)
    case False{} AC.AcpTurn{cwd, mcp, _, _, sid, _}:
      AC.Acp.rpc(2n, "session/resume", J.Json.obj([J.KV{"sessionId", J.Str{sid}}, J.KV{"cwd", J.Str{cwd}}, J.KV{"mcpServers", AC.Acp.mcp(mcp)}]))

def Omp.open(+t: AC.AcpTurn) -> String:
  Omp.open.k(String.is_empty(AC.Acp.session(t)), t)

def Omp.renew(t: AC.AcpTurn) -> String:
  match t:
    case AC.AcpTurn{cwd, mcp, _, _, _, _}:
      Omp.new.rpc(7n, cwd, mcp)

def Omp.set(+id: Nat, +sid: String, +key: String, +v: String) -> String:
  AC.Acp.rpc(id, "session/set_config_option", J.Json.obj([J.KV{"sessionId", J.Str{sid}}, J.KV{"configId", J.Str{key}}, J.KV{"value", J.Str{v}}]))

def Omp.say(+sid: String, +t: AC.AcpTurn) -> String:
  AC.Acp.say.rpc(sid, Omp.text(t))

# State
# -----

def Omp.ended(a: AC.Acp) -> AC.Acp:
  match a:
    case AC.Acp{s, b, _, k}:
      AC.Acp{s, b, True{}, k}

def Omp.with_sid(a: AC.Acp, +sid: String) -> AC.Acp:
  match a:
    case AC.Acp{_, b, d, k}:
      AC.Acp{sid, b, d, k}

def Omp.sid(a: AC.Acp) -> String:
  match a:
    case AC.Acp{s, _, _, _}:
      s

def Omp.none(a: AC.Acp) -> AC.AcpOut:
  AC.AcpOut{a, Nil{}, Nil{}, Nil{}}

def Omp.notice(+msg: String) -> String:
  AC.Acp.event("notice", [J.KV{"message", J.Str{msg}}])

# Failures
# --------

def Omp.signin(+low: String) -> Bool:
  Bool.or(Bool.or(String.contains(low, "no api key"), String.contains(low, "no model selected")), Bool.or(String.contains(low, "/login"), String.contains(low, "unauthorized")))

def Omp.hint.k(+low: String, +msg: String) -> String:
  Bool.pick(String, String.contains(low, "unknown acp model"), msg ++ " (pick another Oh My Pi model in the composer)",
    Bool.pick(String, Omp.signin(low), msg ++ " (sign Oh My Pi in once: run `omp` and use /login, or set the provider's API key)", msg))

def Omp.hint(+msg: String) -> String:
  Omp.hint.k(String.to_lower(String.take(msg, 400n)), msg)

def Omp.error(+o: J.Json) -> String:
  J.Json.get_str(J.Json.get_obj(o, "error"), "message", "omp failed")

def Omp.fail(a: AC.Acp, +msg: String) -> AC.AcpOut:
  AC.AcpOut{Omp.ended(a), Nil{}, [AC.Acp.failed(Omp.hint(msg))], Nil{}}

def Omp.lost(+msg: String) -> Bool:
  String.contains(msg, "session not found")

# Replies to our requests (by id)
# -------------------------------

# after the session opens: the model, the thinking level, then the prompt
# (each only when the thread names one)
def Omp.after.e(+a: AC.Acp, +t: OmpTurn) -> AC.AcpOut:
  Bool.pick(AC.AcpOut, String.is_empty(Omp.effort(t)), AC.AcpOut{a, [Omp.say(Omp.sid(a), Omp.acp(t))], Nil{}, Nil{}},
    AC.AcpOut{a, [Omp.set(5n, Omp.sid(a), "thinking", Omp.effort(t))], Nil{}, Nil{}})

def Omp.after.m(+a: AC.Acp, +t: OmpTurn) -> AC.AcpOut:
  Bool.pick(AC.AcpOut, String.is_empty(Omp.model(t)), Omp.after.e(a, t),
    AC.AcpOut{a, [Omp.set(4n, Omp.sid(a), "model", Omp.model(t))], Nil{}, Nil{}})

def Omp.with_emit(o: AC.AcpOut, +more: List<&2, String>) -> AC.AcpOut:
  match o:
    case AC.AcpOut{a, send, emit, asks}:
      AC.AcpOut{a, send, List.append(&2, String, emit, more), asks}

def Omp.opened(a: AC.Acp, +t: OmpTurn, +sid: String, +more: List<&2, String>) -> AC.AcpOut:
  Omp.with_emit(Omp.after.m(Omp.with_sid(a, sid), t), AC.Acp.event("thread.started", [J.KV{"thread_id", J.Str{sid}}]) <> more)

def Omp.renewed.msg(+old: String) -> String:
  "Oh My Pi could not resume its session " ++ old ++ ", so it started a new one without the earlier conversation. This thread's history in Backplane is kept."

def Omp.reopen(renew: Bool, a: AC.Acp, +t: OmpTurn, +o: J.Json) -> AC.AcpOut:
  match renew:
    case True{}:
      AC.AcpOut{a, [Omp.renew(Omp.acp(t))], Nil{}, Nil{}}
    case False{}:
      Omp.fail(a, Omp.error(o))

def Omp.reply.k(i: Nat, ok: Bool, a: AC.Acp, +t: OmpTurn, +o: J.Json) -> AC.AcpOut:
  match i ok:
    case 1n True{}:
      AC.AcpOut{a, [Omp.open(Omp.acp(t))], Nil{}, Nil{}}
    case 2n True{}:
      Omp.opened(a, t, J.Json.get_str(J.Json.get_obj(o, "result"), "sessionId", Omp.session(t)), Nil{})
    case 2n False{}:
      Omp.reopen(Bool.and(Bool.not(String.is_empty(Omp.session(t))), Omp.lost(Omp.error(o))), a, t, o)
    case 7n True{}:
      Omp.opened(a, t, J.Json.get_str(J.Json.get_obj(o, "result"), "sessionId", ""), [Omp.notice(Omp.renewed.msg(Omp.session(t)))])
    case 4n True{}:
      Omp.after.e(a, t)
    case 5n True{}:
      AC.AcpOut{a, [Omp.say(Omp.sid(a), Omp.acp(t))], Nil{}, Nil{}}
    case 3n True{}:
      AC.Acp.finished(a)
    case _ False{}:
      Omp.fail(a, Omp.error(o))
    case _ True{}:
      Omp.none(a)

# digits as a number (no Nat.read: laws normalize this)
def Omp.num.c(+c: U32, +acc: Nat) -> Nat:
  Bool.pick(Nat, Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)), Nat.add(Nat.mul(acc, 10n), U32.to_nat((c - 48 : U32))), acc)

def Omp.num(s: String, +acc: Nat) -> Nat:
  match s:
    case SNil{}:
      acc
    case SCon{Chr{+c}, t}:
      Omp.num(t, Omp.num.c(c, acc))

def Omp.id(+o: J.Json) -> Nat:
  Omp.num(J.Json.as_raw(J.Json.get(o, "id"), "0"), 0n)

# Elicitations
# ------------

def Omp.str1(x: J.Json) -> String:
  match x:
    case J.Str{v}:
      v
    case other:
      J.Json.show(other)

def Omp.has(xs: List<&2, J.Json>, +x: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case h <> t:
      Bool.or(String.eq(Omp.str1(h), x), Omp.has(t, x))

def Omp.strs(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case h <> t:
      Omp.str1(h) <> Omp.strs(t)

# the labels a session answer may name ("Approve <what> for this session")
def Omp.session.label(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case +x <> t:
      Bool.pick(String, Bool.and(String.starts_with(x, "Approve "), String.ends_with(x, " for this session")), x, Omp.session.label(t))

def Omp.member(xs: List<&2, String>, +x: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case +h <> t:
      Bool.or(String.eq(h, x), Omp.member(t, x))

def Omp.once.label(+xs: List<&2, String>) -> String:
  Bool.pick(String, Omp.member(xs, "Approve Once"), "Approve Once", "Approve")

# an approval's message: "Allow tool: <name>", then what it runs
def Omp.lines(+msg: String) -> List<&2, String>:
  String.split(String.take(msg, 2000n), '\n')

def Omp.tool.of(ls: List<&2, String>) -> String:
  match ls:
    case l <> _:
      String.trim(String.drop(l, 12n))
    case Nil{}:
      "tool"

def Omp.detail.of(ls: List<&2, String>) -> String:
  match ls:
    case _ <> rest:
      String.take(String.trim(String.join(rest, "\n")), 600n)
    case Nil{}:
      ""

def Omp.approval.line(+o: J.Json, +p: J.Json, +labels: List<&2, String>) -> String:
  DL.Dlg.line(DL.Dlg.id(o), "approval", "elicit", [J.KV{"tool", J.Str{Omp.tool.of(Omp.lines(J.Json.get_str(p, "message", "")))}},
    J.KV{"detail", J.Str{Omp.detail.of(Omp.lines(J.Json.get_str(p, "message", "")))}}, J.KV{"key", J.Str{"value"}},
    J.KV{"once", J.Str{Omp.once.label(labels)}}, J.KV{"session", J.Str{Omp.session.label(labels)}}, J.KV{"deny", J.Str{"Deny"}}])

# Backplane's own tools are allowed at once (as Pi's extension does), and
# all of them in full access; the rest wait for the person
def Omp.approval.k(now: Bool, +a: AC.Acp, +line: String) -> AC.AcpOut:
  match now:
    case True{}:
      AC.AcpOut{a, [DL.Dlg.reply(line, "accept")], Nil{}, Nil{}}
    case False{}:
      AC.AcpOut{a, Nil{}, Nil{}, [line]}

def Omp.approval(ask: Bool, +a: AC.Acp, +o: J.Json, +p: J.Json, +v: J.Json) -> AC.AcpOut:
  Omp.approval.k(Bool.or(Bool.not(ask), String.starts_with(Omp.tool.of(Omp.lines(J.Json.get_str(p, "message", ""))), "mcp__backplane__")), a,
    Omp.approval.line(o, p, Omp.strs(J.Json.elems(J.Json.get_obj(v, "enum")))))

def Omp.consts(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case +h <> t:
      J.Json.get_str(h, "const", J.Json.get_str(h, "title", "")) <> Omp.consts(t)

# a question's choices: an enum's, else anyOf's consts
def Omp.choices(+v: J.Json) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.eq(J.Json.show(J.Json.get_obj(v, "enum")), "null"), Omp.consts(J.Json.elems(J.Json.get_obj(v, "anyOf"))), Omp.strs(J.Json.elems(J.Json.get_obj(v, "enum"))))

def Omp.question.text(+p: J.Json, +v: J.Json) -> String:
  Bool.pick(String, String.is_empty(J.Json.get_str(v, "title", "")), J.Json.get_str(p, "message", ""), J.Json.get_str(v, "title", ""))

def Omp.question(+o: J.Json, +p: J.Json, +key: String, +v: J.Json) -> String:
  DL.Dlg.line(DL.Dlg.id(o), "question", "elicit", [J.KV{"tool", J.Str{"Oh My Pi"}}, J.KV{"detail", J.Str{Omp.question.text(p, v)}},
    J.KV{"options", J.Str{Bool.pick(String, String.eq(J.Json.get_str(v, "type", ""), "boolean"), "Yes\nNo", String.join(Omp.choices(v), "\n"))}},
    J.KV{"key", J.Str{key}}, J.KV{"bool", J.Flag{String.eq(J.Json.get_str(v, "type", ""), "boolean")}}])

# a form Backplane cannot show (several questions, a multiple choice): declined, said
def Omp.decline(+o: J.Json) -> String:
  DL.Dlg.result(DL.Dlg.id(o), J.Json.obj([J.KV{"action", J.Str{"decline"}}]))

def Omp.declined.msg() -> String:
  "Oh My Pi asked something Backplane cannot show yet (several questions at once, or a multiple choice), so it was declined."

def Omp.form.pos(+props: J.Json) -> Nat:
  Bool.pick(Nat, Bool.not(String.eq(J.Json.show(J.Json.get_obj(props, "value")), "null")), 0n,
    Bool.pick(Nat, Bool.and(Bool.not(String.eq(J.Json.show(J.Json.get_obj(props, "q0")), "null")), String.eq(J.Json.show(J.Json.get_obj(props, "q1")), "null")), 1n, 2n))

def Omp.value.k(approval: Bool, ask: Bool, +a: AC.Acp, +o: J.Json, +p: J.Json, +v: J.Json) -> AC.AcpOut:
  match approval:
    case True{}:
      Omp.approval(ask, a, o, p, v)
    case False{}:
      AC.AcpOut{a, Nil{}, Nil{}, [Omp.question(o, p, "value", v)]}

# an approval: one string field whose choices end with Deny, under
# "Allow tool: ..."
def Omp.is_approval(+p: J.Json, +v: J.Json) -> Bool:
  Bool.and(String.starts_with(J.Json.get_str(p, "message", ""), "Allow tool: "), Omp.has(J.Json.elems(J.Json.get_obj(v, "enum")), "Deny"))

def Omp.q0.k(multi: Bool, +a: AC.Acp, +o: J.Json, +p: J.Json, +v: J.Json) -> AC.AcpOut:
  match multi:
    case True{}:
      AC.AcpOut{a, [Omp.decline(o)], [Omp.notice(Omp.declined.msg())], Nil{}}
    case False{}:
      AC.AcpOut{a, Nil{}, Nil{}, [Omp.question(o, p, "q0", v)]}

def Omp.form.k(i: Nat, ask: Bool, +a: AC.Acp, +o: J.Json, +p: J.Json, +props: J.Json) -> AC.AcpOut:
  match i:
    case 0n:
      Omp.value.k(Omp.is_approval(p, J.Json.get_obj(props, "value")), ask, a, o, p, J.Json.get_obj(props, "value"))
    case 1n:
      Omp.q0.k(String.eq(J.Json.get_str(J.Json.get_obj(props, "q0"), "type", ""), "array"), a, o, p, J.Json.get_obj(props, "q0"))
    case _:
      AC.AcpOut{a, [Omp.decline(o)], [Omp.notice(Omp.declined.msg())], Nil{}}

def Omp.elicit(ask: Bool, +a: AC.Acp, +o: J.Json) -> AC.AcpOut:
  Omp.form.k(Omp.form.pos(J.Json.get_obj(J.Json.get_obj(J.Json.get_obj(o, "params"), "requestedSchema"), "properties")), ask, a, o,
    J.Json.get_obj(o, "params"), J.Json.get_obj(J.Json.get_obj(J.Json.get_obj(o, "params"), "requestedSchema"), "properties"))

# The lines
# ---------

def Omp.req.k(elicit: Bool, +a: AC.Acp, +t: OmpTurn, +o: J.Json) -> AC.AcpOut:
  match elicit:
    case True{}:
      Omp.elicit(AC.Acp.ask_of(Omp.acp(t)), a, o)
    case False{}:
      AC.Acp.line.k(True{}, a, Omp.acp(t), o)

def Omp.line.k(req: Bool, +a: AC.Acp, +t: OmpTurn, +o: J.Json) -> AC.AcpOut:
  match req:
    case True{}:
      Omp.req.k(String.eq(J.Json.get_str(o, "method", ""), "elicitation/create"), a, t, o)
    case False{}:
      Omp.reply.k(Omp.id(o), String.eq(J.Json.show(J.Json.get_obj(o, "error")), "null"), a, t, o)

def Omp.line.parsed(m: Maybe<&2, J.Json>, +a: AC.Acp, +t: OmpTurn) -> AC.AcpOut:
  match m:
    case Some{+o}:
      Omp.line.k(Bool.not(String.is_empty(J.Json.get_str(o, "method", ""))), a, t, o)
    case None{}:
      Omp.none(a)

# one line from omp
def Omp.line(+a: AC.Acp, +t: OmpTurn, line: String) -> AC.AcpOut:
  Omp.line.parsed(J.Json.parse(line), a, t)
