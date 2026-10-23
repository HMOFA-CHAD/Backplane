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
#   instructions first;
# - a tool call starts before its input is known (tool_call names only
#   the tool, a shell's reads "bash"): it is logged once, at its first
#   tool_call_update, named by what it does (the command, the file, the
#   pattern, the URL);
# - a failure says how to fix opencode (not Grok's sign-in).
# Request ids: 1 initialize, 2 session/new or session/resume, 7
# session/new after a lost session, 3 the prompt.

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

def Ocp.hint.k(+low: String, +msg: String) -> String:
  Bool.pick(String, String.contains(low, "model not found"), msg ++ " (pick another opencode model in the composer)",
    Bool.pick(String, Ocp.signin(low), msg ++ " (sign in once with `opencode auth login`)", msg))

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
def Ocp.opened(fresh: Bool, a: AC.Acp, +t: AC.AcpTurn, +sid: String) -> AC.AcpOut:
  AC.AcpOut{Ocp.with_sid(a, sid), [AC.Acp.say.k(fresh, t, sid)], [AC.Acp.event("thread.started", [J.KV{"thread_id", J.Str{sid}}])], Nil{}}

# session/new answers its id; session/resume none (the thread's own)
def Ocp.answered(a: AC.Acp, +t: AC.AcpTurn, +o: J.Json) -> AC.AcpOut:
  Ocp.opened(String.is_empty(AC.Acp.session(t)), a, t, J.Json.get_str(J.Json.get_obj(o, "result"), "sessionId", AC.Acp.session(t)))

# a resume that failed because the session is gone opens a fresh one; any
# other failure ends the turn
def Ocp.reopen(renew: Bool, a: AC.Acp, +t: AC.AcpTurn, +o: J.Json) -> AC.AcpOut:
  match renew:
    case True{}:
      AC.AcpOut{a, [Ocp.renew(t)], Nil{}, Nil{}}
    case False{}:
      Ocp.fail(a, Ocp.error(o))

def Ocp.reply.k(i: Nat, ok: Bool, a: AC.Acp, +t: AC.AcpTurn, +o: J.Json) -> AC.AcpOut:
  match i ok:
    case 1n True{}:
      AC.AcpOut{a, [Ocp.open(t)], Nil{}, Nil{}}
    case 2n True{}:
      Ocp.answered(a, t, o)
    case 2n False{}:
      Ocp.reopen(Bool.and(Bool.not(String.is_empty(AC.Acp.session(t))), Ocp.lost(Ocp.error(o))), a, t, o)
    case 7n True{}:
      Ocp.opened(True{}, a, t, J.Json.get_str(J.Json.get_obj(o, "result"), "sessionId", ""))
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

def Ocp.line.k(req: Bool, +a: AC.Acp, +t: AC.AcpTurn, +o: J.Json) -> AC.AcpOut:
  match req:
    case True{}:
      Ocp.req.k(String.eq(J.Json.get_str(o, "method", ""), "session/update"), a, t, o)
    case False{}:
      Ocp.reply.k(Ocp.id(o), String.eq(J.Json.show(J.Json.get_obj(o, "error")), "null"), a, t, o)

def Ocp.line.parsed(m: Maybe<&2, J.Json>, +a: AC.Acp, +t: AC.AcpTurn) -> AC.AcpOut:
  match m:
    case Some{+o}:
      Ocp.line.k(Bool.not(String.is_empty(J.Json.get_str(o, "method", ""))), a, t, o)
    case None{}:
      AC.AcpOut{a, Nil{}, Nil{}, Nil{}}

# one line from opencode
def Ocp.line(+a: AC.Acp, +t: AC.AcpTurn, line: String) -> AC.AcpOut:
  Ocp.line.parsed(J.Json.parse(line), a, t)
