import Base
import ./json.bend as J
import ./acp.bend as AC

# opencode over ACP (`opencode acp`)
# ----------------------------------
# Grok's translator (acp.bend) with what opencode does its own way:
# - a thread's session is taken up again with session/resume (opencode
#   2.1 offers it), which does not replay the whole conversation as
#   session/load did on every turn; a session opencode no longer has, or
#   one made in another folder, opens afresh (7) with Backplane's
#   instructions first, and the person is told once ("notice", an info
#   row: the new session has none of the earlier conversation); nothing
#   else falls back;
# - a tool call starts before its input is known (tool_call names only
#   the tool, a shell's reads "bash"): it is logged once, at its first
#   tool_call_update, named by what it does (the command, the file, the
#   pattern, the URL);
# - a failure says how to fix opencode (not Grok's sign-in).
# - the thread's model is the session's own pick (session/set_config_option
#   "model", 5 in a fresh session, 15 in a resumed one), sent before the
#   prompt: opencode takes a session's pick over its agent's model and that
#   over the config's "model" (OPENCODE_CONFIG_CONTENT), so an agent with a
#   model of its own (a default agent's) never quietly runs instead; a
#   model it refuses fails the turn. No model picked: opencode's own
#   default (its default agent's model, else its config's).
# Request ids: 1 initialize, 2 session/new or session/resume, 7
# session/new after a lost session, 5/15 the model, 3 the prompt.

type OcpTurn is Data:
  OcpTurn{acp: AC.AcpTurn, model: String}

def Ocp.acp(t: OcpTurn) -> AC.AcpTurn:
  match t:
    case OcpTurn{a, _}:
      a

def Ocp.model(t: OcpTurn) -> String:
  match t:
    case OcpTurn{_, m}:
      m

# whether the thread picked a model ("" and "default" are opencode's own)
def Ocp.picked(+m: String) -> Bool:
  Bool.not(Bool.or(String.is_empty(m), String.eq(m, "default")))

def Ocp.set_model(+id: Nat, +sid: String, +model: String) -> String:
  AC.Acp.rpc(id, "session/set_config_option", J.Json.obj([J.KV{"sessionId", J.Str{sid}}, J.KV{"configId", J.Str{"model"}}, J.KV{"value", J.Str{model}}]))

def Ocp.new.rpc(+id: Nat, +cwd: String, +mcp: String) -> String:
  AC.Acp.rpc(id, "session/new", J.Json.obj([J.KV{"cwd", J.Str{cwd}}, J.KV{"mcpServers", AC.Acp.mcp(mcp)}]))

def Ocp.open.k(fresh: Bool, t: AC.AcpTurn) -> String:
  match fresh t:
    case True{} AC.AcpTurn{cwd, mcp, _, _, _, _}:
      Ocp.new.rpc(2n, cwd, mcp)
    case False{} AC.AcpTurn{cwd, mcp, _, _, sid, _}:
      AC.Acp.rpc(2n, "session/resume", J.Json.obj([J.KV{"sessionId", J.Str{sid}}, J.KV{"cwd", J.Str{cwd}}, J.KV{"mcpServers", AC.Acp.mcp(mcp)}]))

# a new session or the thread's own, resumed
def Ocp.open(+t: AC.AcpTurn) -> String:
  Ocp.open.k(String.is_empty(AC.Acp.session(t)), t)

def Ocp.renew(t: AC.AcpTurn) -> String:
  match t:
    case AC.AcpTurn{cwd, mcp, _, _, _, _}:
      Ocp.new.rpc(7n, cwd, mcp)

def Ocp.cwd(t: AC.AcpTurn) -> String:
  match t:
    case AC.AcpTurn{cwd, _, _, _, _, _}:
      cwd

def Ocp.ended(a: AC.Acp) -> AC.Acp:
  match a:
    case AC.Acp{s, b, _, k}:
      AC.Acp{s, b, True{}, k}

def Ocp.with_sid(a: AC.Acp, +sid: String) -> AC.Acp:
  match a:
    case AC.Acp{_, b, d, k}:
      AC.Acp{sid, b, d, k}

def Ocp.mark(+id: String) -> String:
  "\n" ++ id ++ "\n"

# whether the call is logged already
def Ocp.seen(a: AC.Acp, +id: String) -> Bool:
  match a:
    case AC.Acp{_, _, _, k}:
      String.contains(k, Ocp.mark(id))

def Ocp.saw(a: AC.Acp, +id: String) -> AC.Acp:
  match a:
    case AC.Acp{s, b, d, k}:
      AC.Acp{s, b, d, k ++ Ocp.mark(id)}

# Failures
# --------

def Ocp.signin(+low: String) -> Bool:
  Bool.or(Bool.or(String.contains(low, "auth"), String.contains(low, "login")), Bool.or(String.contains(low, "no models are available"), String.contains(low, "api key")))

# (a provider that refused the model's sign-in is not opencode's own: an
# expired OAuth sign-in does it, and with no model picked opencode's
# configured default agent chose the model)
def Ocp.hint.k(+low: String, +msg: String) -> String:
  Bool.pick(String, String.contains(low, "model not found"), msg ++ " (pick another opencode model in the composer)",
    Bool.pick(String, String.contains(low, "provider authentication required"),
      msg ++ " (the model's provider refused opencode's sign-in, as an expired OAuth sign-in does: run `opencode auth login` for that provider; with no model picked, opencode's configured default agent chose it)",
      Bool.pick(String, Ocp.signin(low), msg ++ " (sign in once with `opencode auth login`)", msg)))

# the reason, and how to fix it when that is known
def Ocp.hint(+msg: String) -> String:
  Ocp.hint.k(String.to_lower(msg), msg)

# opencode no longer has the session, or it was made in another folder
def Ocp.lost(+msg: String) -> Bool:
  Bool.or(String.contains(msg, "session not found"), String.contains(msg, "does not belong to cwd"))

def Ocp.error(+o: J.Json) -> String:
  J.Json.get_str(J.Json.get_obj(o, "error"), "message", "opencode failed")

def Ocp.fail(a: AC.Acp, +msg: String) -> AC.AcpOut:
  AC.AcpOut{Ocp.ended(a), Nil{}, [AC.Acp.failed(Ocp.hint(msg))], Nil{}}

# Replies to our requests (by id)
# -------------------------------

# the session is open: note it, then the prompt (Backplane's instructions
# first in a fresh one)
# the model first when the thread picked one, else the prompt
def Ocp.next(+fresh: Bool, +t: OcpTurn, +sid: String) -> String:
  Bool.pick(String, Ocp.picked(Ocp.model(t)), Ocp.set_model(Bool.pick(Nat, fresh, 5n, 15n), sid, Ocp.model(t)), AC.Acp.say.k(fresh, Ocp.acp(t), sid))

def Ocp.opened(+fresh: Bool, a: AC.Acp, +t: OcpTurn, +sid: String) -> AC.AcpOut:
  AC.AcpOut{Ocp.with_sid(a, sid), [Ocp.next(fresh, t, sid)], [AC.Acp.event("thread.started", [J.KV{"thread_id", J.Str{sid}}])], Nil{}}

def Ocp.sid(a: AC.Acp) -> String:
  match a:
    case AC.Acp{s, _, _, _}:
      s

# the model taken: the prompt (Backplane's instructions first when fresh)
def Ocp.say(fresh: Bool, +a: AC.Acp, +t: OcpTurn) -> AC.AcpOut:
  AC.AcpOut{a, [AC.Acp.say.k(fresh, Ocp.acp(t), Ocp.sid(a))], Nil{}, Nil{}}

def Ocp.unmodel(+t: OcpTurn, +msg: String) -> String:
  "opencode refused the model " ++ Ocp.model(t) ++ ": " ++ msg

# what the person is told once a lost session was replaced: the agent
# starts without the earlier conversation (Backplane's history is kept)
def Ocp.renewed.msg(+old: String) -> String:
  "opencode could not resume its session " ++ old ++ ", so it started a new one without the earlier conversation. This thread's history in Backplane is kept."

def Ocp.notice(+msg: String) -> String:
  AC.Acp.event("notice", [J.KV{"message", J.Str{msg}}])

# the fresh session that replaced a lost one: opened as any, and said
def Ocp.renewed.k(o: AC.AcpOut, +old: String) -> AC.AcpOut:
  match o:
    case AC.AcpOut{a, send, emit, asks}:
      AC.AcpOut{a, send, List.append(&2, String, emit, [Ocp.notice(Ocp.renewed.msg(old))]), asks}

def Ocp.renewed(a: AC.Acp, +t: OcpTurn, +o: J.Json) -> AC.AcpOut:
  Ocp.renewed.k(Ocp.opened(True{}, a, t, J.Json.get_str(J.Json.get_obj(o, "result"), "sessionId", "")), AC.Acp.session(Ocp.acp(t)))

# session/new answers its id; session/resume none (the thread's own)
def Ocp.answered(a: AC.Acp, +t: OcpTurn, +o: J.Json) -> AC.AcpOut:
  Ocp.opened(String.is_empty(AC.Acp.session(Ocp.acp(t))), a, t, J.Json.get_str(J.Json.get_obj(o, "result"), "sessionId", AC.Acp.session(Ocp.acp(t))))

# a resume that failed because the session is gone opens a fresh one; any
# other failure ends the turn
def Ocp.reopen(renew: Bool, a: AC.Acp, +t: OcpTurn, +o: J.Json) -> AC.AcpOut:
  match renew:
    case True{}:
      AC.AcpOut{a, [Ocp.renew(Ocp.acp(t))], Nil{}, Nil{}}
    case False{}:
      Ocp.fail(a, Ocp.error(o))

def Ocp.reply.k(i: Nat, ok: Bool, a: AC.Acp, +t: OcpTurn, +o: J.Json) -> AC.AcpOut:
  match i ok:
    case 1n True{}:
      AC.AcpOut{a, [Ocp.open(Ocp.acp(t))], Nil{}, Nil{}}
    case 2n True{}:
      Ocp.answered(a, t, o)
    case 2n False{}:
      Ocp.reopen(Bool.and(Bool.not(String.is_empty(AC.Acp.session(Ocp.acp(t)))), Ocp.lost(Ocp.error(o))), a, t, o)
    case 5n True{}:
      Ocp.say(True{}, a, t)
    case 15n True{}:
      Ocp.say(False{}, a, t)
    case 5n False{}:
      Ocp.fail(a, Ocp.unmodel(t, Ocp.error(o)))
    case 15n False{}:
      Ocp.fail(a, Ocp.unmodel(t, Ocp.error(o)))
    case 7n True{}:
      Ocp.renewed(a, t, o)
    case 3n True{}:
      AC.Acp.finished(a)
    case _ False{}:
      Ocp.fail(a, Ocp.error(o))
    case _ True{}:
      AC.AcpOut{a, Nil{}, Nil{}, Nil{}}

# digits as a number (no Nat.read: laws normalize this)
def Ocp.num.c(+c: U32, +acc: Nat) -> Nat:
  Bool.pick(Nat, Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)), Nat.add(Nat.mul(acc, 10n), U32.to_nat((c - 48 : U32))), acc)

def Ocp.num(s: String, +acc: Nat) -> Nat:
  match s:
    case SNil{}:
      acc
    case SCon{Chr{+c}, t}:
      Ocp.num(t, Ocp.num.c(c, acc))

def Ocp.id(+o: J.Json) -> Nat:
  Ocp.num(J.Json.as_raw(J.Json.get(o, "id"), "0"), 0n)

# Tool calls
# ----------

# a path in the thread's folder, from it
def Ocp.rel(+cwd: String, +p: String) -> String:
  Bool.pick(String, Bool.and(Bool.not(String.is_empty(cwd)), String.starts_with(p, cwd ++ "/")), String.drop(p, Nat.add(String.length(cwd), 1n)), p)

# what a call works on: its file, pattern, URL or query, else the first
# place it names ("" for none)
def Ocp.where.k(+raw: J.Json, +locs: List<&2, J.Json>) -> String:
  AC.Acp.or(J.Json.get_str(raw, "filePath", J.Json.get_str(raw, "path", "")),
    AC.Acp.or(J.Json.get_str(raw, "pattern", J.Json.get_str(raw, "url", J.Json.get_str(raw, "query", ""))),
      J.Json.get_str(Maybe.default(&2, J.Json, List.head(&2, J.Json, locs), J.Null{}), "path", "")))

def Ocp.where(+u: J.Json, +cwd: String) -> String:
  Ocp.rel(cwd, Ocp.where.k(J.Json.get_obj(u, "rawInput"), J.Json.elems(J.Json.get_obj(u, "locations"))))

# the call's line: the tool's title (a shell's is its command) and what it
# works on, unless the title already says it
def Ocp.say.k(+title: String, +what: String) -> String:
  Bool.pick(String, Bool.or(String.is_empty(what), String.contains(title, what)), title, title ++ " " ++ what)

def Ocp.what(+u: J.Json, +cwd: String) -> String:
  Ocp.say.k(AC.Acp.or(J.Json.get_str(u, "title", ""), AC.Acp.or(J.Json.get_str(u, "kind", ""), "tool")), Ocp.where(u, cwd))

def Ocp.log(+u: J.Json, +cwd: String) -> String:
  AC.Acp.event("item.completed", [J.KV{"item", J.Json.obj([J.KV{"type", J.Str{"command_execution"}}, J.KV{"id", J.Str{J.Json.get_str(u, "toolCallId", "")}},
    J.KV{"command", J.Str{Ocp.what(u, cwd)}}])}])

def Ocp.finished(+u: J.Json) -> Bool:
  Bool.or(String.eq(J.Json.get_str(u, "status", ""), "completed"), String.eq(J.Json.get_str(u, "status", ""), "failed"))

# a call that has run ("tool.done": the hub snapshots the design then)
def Ocp.done.line(+u: J.Json) -> List<&2, String>:
  Bool.pick(List<&2, String>, Ocp.finished(u), [AC.Acp.event("tool.done", [J.KV{"id", J.Str{J.Json.get_str(u, "toolCallId", "")}}])], Nil{})

# an update of a call: logged the first time (its input is known then),
# its end told every time it ends
def Ocp.update.k(seen: Bool, a: AC.Acp, +u: J.Json, +cwd: String) -> AC.AcpOut:
  match seen:
    case True{}:
      AC.AcpOut{a, Nil{}, Ocp.done.line(u), Nil{}}
    case False{}:
      AC.AcpOut{Ocp.saw(a, J.Json.get_str(u, "toolCallId", "")), Nil{}, Ocp.log(u, cwd) <> Ocp.done.line(u), Nil{}}

# tool_call (no input yet) waits for its first update; the rest is Grok's
def Ocp.tool.k(i: Nat, +a: AC.Acp, +t: AC.AcpTurn, +o: J.Json) -> AC.AcpOut:
  match i:
    case 0n:
      AC.AcpOut{a, Nil{}, Nil{}, Nil{}}
    case 1n:
      Ocp.update.k(Ocp.seen(a, J.Json.get_str(J.Json.get_obj(J.Json.get_obj(o, "params"), "update"), "toolCallId", "")), a,
        J.Json.get_obj(J.Json.get_obj(o, "params"), "update"), Ocp.cwd(t))
    case _:
      AC.Acp.line.k(True{}, a, t, o)

# updates before the session is open are not this turn's (Grok's rule)
def Ocp.update(open: Bool, +a: AC.Acp, +t: AC.AcpTurn, +o: J.Json) -> AC.AcpOut:
  match open:
    case True{}:
      Ocp.tool.k(AC.Acp.pos(["tool_call", "tool_call_update"], J.Json.get_str(J.Json.get_obj(J.Json.get_obj(o, "params"), "update"), "sessionUpdate", ""), 0n), a, t, o)
    case False{}:
      AC.Acp.line.k(True{}, a, t, o)

def Ocp.req.k(upd: Bool, +a: AC.Acp, +t: AC.AcpTurn, +o: J.Json) -> AC.AcpOut:
  match upd:
    case True{}:
      Ocp.update(AC.Acp.open_now(a), a, t, o)
    case False{}:
      AC.Acp.line.k(True{}, a, t, o)

def Ocp.line.k(req: Bool, +a: AC.Acp, +t: OcpTurn, +o: J.Json) -> AC.AcpOut:
  match req:
    case True{}:
      Ocp.req.k(String.eq(J.Json.get_str(o, "method", ""), "session/update"), a, Ocp.acp(t), o)
    case False{}:
      Ocp.reply.k(Ocp.id(o), String.eq(J.Json.show(J.Json.get_obj(o, "error")), "null"), a, t, o)

def Ocp.line.parsed(m: Maybe<&2, J.Json>, +a: AC.Acp, +t: OcpTurn) -> AC.AcpOut:
  match m:
    case Some{+o}:
      Ocp.line.k(Bool.not(String.is_empty(J.Json.get_str(o, "method", ""))), a, t, o)
    case None{}:
      AC.AcpOut{a, Nil{}, Nil{}, Nil{}}

# one line from opencode
def Ocp.line(+a: AC.Acp, +t: OcpTurn, line: String) -> AC.AcpOut:
  Ocp.line.parsed(J.Json.parse(line), a, t)

# Models (Settings and the picker)
# --------------------------------
# The hub's Oc.models.sh writes, one per line: each model opencode lists
# (`opencode models`, "provider/model"; opencode 2 has no --verbose, the
# flag that once gave names, and fails with its usage when given it), then
# "!exit <code>\t<its last error line>" when listing failed, then
# "!auth\t<provider>\t<method>" for each sign-in `opencode auth list`
# shows (names and methods only: a token never leaves opencode). What it
# says is the CLI line Settings shows for opencode on every client: a list
# that failed or is empty says why, never as an empty list that worked.

def Ocm.cols(+l: String) -> List<&2, String>:
  String.split(l, '\t')

def Ocm.id(+l: String) -> String:
  Maybe.default(&2, String, List.head(&2, String, Ocm.cols(l)), "")

def Ocm.rest(+l: String) -> String:
  String.join(List.drop(&2, String, Ocm.cols(l), 1n), " ")

# a model line: "provider/model", a name after a tab allowed
def Ocm.model(+l: String) -> Bool:
  Bool.and(Bool.not(String.starts_with(l, "!")), Bool.and(String.contains(Ocm.id(l), "/"), Bool.not(String.contains(Ocm.id(l), " "))))

def Ocm.models.k(ok: Bool, +l: String, rest: List<&2, String>) -> List<&2, String>:
  match ok:
    case True{}:
      Ocm.id(l) <> rest
    case False{}:
      rest

def Ocm.models.go(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      Ocm.models.k(Ocm.model(l), l, Ocm.models.go(t))

def Ocm.models(+out: String) -> List<&2, String>:
  Ocm.models.go(String.lines(out))

def Ocm.labels.k(ok: Bool, +l: String, rest: List<&2, J.KV>) -> List<&2, J.KV>:
  match ok:
    case True{}:
      J.KV{Ocm.id(l), J.Str{Ocm.rest(l)}} <> rest
    case False{}:
      rest

def Ocm.labels.go(ls: List<&2, String>) -> List<&2, J.KV>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      Ocm.labels.k(Bool.and(Ocm.model(l), Bool.not(String.is_empty(Ocm.rest(l)))), l, Ocm.labels.go(t))

# a label per model that has a name ("default" is opencode's own choice)
def Ocm.labels(+out: String) -> List<&2, J.KV>:
  J.KV{"default", J.Str{"opencode's configured default"}} <> Ocm.labels.go(String.lines(out))

# the "!exit" line, "" when listing worked
def Ocm.failed(ls: List<&2, String>) -> String:
  match ls:
    case Nil{}:
      ""
    case +l <> t:
      Bool.pick(String, String.starts_with(l, "!exit "), l, Ocm.failed(t))

def Ocm.timed(+c: String) -> Bool:
  Bool.or(String.eq(c, "124"), Bool.or(String.eq(c, "137"), String.eq(c, "143")))

def Ocm.why.k(timed: Bool, +c: String, +said: String) -> String:
  match timed:
    case True{}:
      "timed out listing models"
    case False{}:
      "could not list models (`opencode models` exited " ++ c ++ Bool.pick(String, String.is_empty(said), "", ": " ++ said) ++ ")"

# why listing failed, from "!exit <code>\t<said>"
def Ocm.why(+f: String) -> String:
  Ocm.why.k(Ocm.timed(Ocm.id(String.drop(f, 6n))), Ocm.id(String.drop(f, 6n)), String.trim(Ocm.rest(String.drop(f, 6n))))

def Ocm.auth.k(ok: Bool, +l: String, rest: List<&2, String>) -> List<&2, String>:
  match ok:
    case True{}:
      (Ocm.id(String.drop(l, 6n)) ++ Bool.pick(String, String.is_empty(Ocm.rest(String.drop(l, 6n))), "", " (" ++ Ocm.rest(String.drop(l, 6n)) ++ ")")) <> rest
    case False{}:
      rest

def Ocm.auth.go(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      Ocm.auth.k(String.starts_with(l, "!auth\t"), l, Ocm.auth.go(t))

# the sign-ins opencode keeps, "OpenAI (OAuth)" each (kept is not valid:
# an expired one shows here and fails its turns)
def Ocm.auth(+out: String) -> List<&2, String>:
  Ocm.auth.go(String.lines(out))

def Ocm.count(+n: Nat) -> String:
  Nat.show(n) ++ Bool.pick(String, String.eq(Nat.show(n), "1"), " model", " models")

def Ocm.signed(+xs: List<&2, String>) -> String:
  Bool.pick(String, List.is_empty(&2, String, xs), "no sign-ins", "sign-ins: " ++ String.join(xs, ", "))

def Ocm.listed.k(none: Bool, +n: Nat, +xs: List<&2, String>) -> String:
  match none:
    case True{}:
      "lists no models: sign in with `opencode auth login`"
    case False{}:
      Ocm.count(n) ++ " · " ++ Ocm.signed(xs)

def Ocm.state.k(+f: String, +n: Nat, +xs: List<&2, String>) -> String:
  Bool.pick(String, String.is_empty(f), Ocm.listed.k(Bool.not(Nat.is_gt(n, 0n)), n, xs), Ocm.why(f))

# what Settings says after the version: the models and sign-ins, or why
# there are none
def Ocm.state(+out: String) -> String:
  Ocm.state.k(Ocm.failed(String.lines(out)), List.length(&2, String, Ocm.models(out)), Ocm.auth(out))

# the problem alone ("" when models were listed)
def Ocm.problem(+out: String) -> String:
  Bool.pick(String, Nat.is_gt(List.length(&2, String, Ocm.models(out)), 0n), "", Ocm.state(out))

# about.opencode: "cli" is the line Settings shows ("" when opencode is not
# installed: Settings says so), "version" the CLI's own (a refresh starts
# from it), "error" why no model can be picked
def Ocm.cli(+version: String, +out: String) -> String:
  Bool.pick(String, String.is_empty(version), "", version ++ " · " ++ Ocm.state(out))

def Ocm.about(+version: String, +out: String) -> J.Json:
  J.Json.obj([J.KV{"cli", J.Str{Ocm.cli(version, out)}}, J.KV{"version", J.Str{version}}, J.KV{"labels", J.Json.obj(Ocm.labels(out))},
    J.KV{"error", J.Str{Bool.pick(String, String.is_empty(version), "", Ocm.problem(out))}}])

# A refresh (models.refresh, when the picker opens on opencode) reads
# opencode's models again into the hub's models info: opencode's list and
# about.opencode are replaced, every other key (and every other provider's
# about) kept as it was, whichever providers there are

def Ocm.strs(xs: List<&2, String>) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      J.Str{x} <> Ocm.strs(t)

def Ocm.keep.k(skip: Bool, +k: String, v: J.Json, rest: List<&2, J.KV>) -> List<&2, J.KV>:
  match skip:
    case True{}:
      rest
    case False{}:
      J.KV{k, v} <> rest

def Ocm.keep.go(fs: J.Json, +drop: List<&2, String>) -> List<&2, J.KV>:
  match fs:
    case J.Field{+k, v, t}:
      Ocm.keep.k(List.contains(~String, ~String.eq, drop, k), k, v, Ocm.keep.go(t, drop))
    case _:
      Nil{}

# an object's fields but those named in drop
def Ocm.keep(o: J.Json, +drop: List<&2, String>) -> List<&2, J.KV>:
  match o:
    case J.Obj{fs}:
      Ocm.keep.go(fs, drop)
    case _:
      Nil{}

# the CLI's version a refresh starts from ("cli" before "version" was kept)
def Ocm.version(+a: J.Json) -> String:
  J.Json.get_str(a, "version", J.Json.get_str(a, "cli", ""))

def Ocm.patch(+j: J.Json, +out: String) -> J.Json:
  J.Json.obj(List.append(&2, J.KV, Ocm.keep(j, ["opencode", "about"]),
    [J.KV{"opencode", J.Json.arr(Ocm.strs(Ocm.models(out)))},
     J.KV{"about", J.Json.obj(List.append(&2, J.KV, Ocm.keep(J.Json.get_obj(j, "about"), ["opencode"]),
       [J.KV{"opencode", Ocm.about(Ocm.version(J.Json.get_obj(J.Json.get_obj(j, "about"), "opencode")), out)}]))}]))
