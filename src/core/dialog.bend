import Base
import ./json.bend as J

# Agents' dialogs
# ---------------
# Asks a runner hands the hub that are neither ACP permission requests nor
# Muse approvals: Pi's and Oh My Pi's extension dialogs (pi.bend,
# omp.bend), and ACP form elicitations. Each becomes one envelope line, method
# "bp/ask", with what the approval or question card shows and what the
# answer must be written back as. The hub opens the ask (mcp.bend's
# Bp.permit) and, once the person answers, Dlg.reply makes the agent's
# line.
#
# params: kind "approval" or "question"; proto "pi" (Pi's
# extension_ui_response) or "elicit" (an ACP elicitation's result); tool
# (an approval's tool: what "Allow for session" remembers); detail (what
# the card says); options (a question's choices, one a line); key (an
# elicitation's field); bool (the answer is yes or no); once, session,
# deny (an elicitation approval's labels). id: the agent's request id, as
# it came.

def Dlg.line(id: J.Json, +kind: String, +proto: String, kvs: List<&2, J.KV>) -> String:
  J.Json.show(J.Json.obj([J.KV{"jsonrpc", J.Str{"2.0"}}, J.KV{"id", id}, J.KV{"method", J.Str{"bp/ask"}},
    J.KV{"params", J.Json.obj(J.KV{"kind", J.Str{kind}} <> J.KV{"proto", J.Str{proto}} <> kvs)}]))

def Dlg.or(+a: String, +b: String) -> String:
  Bool.pick(String, String.is_empty(a), b, a)

def Dlg.approval(+p: J.Json) -> Bool:
  String.eq(J.Json.get_str(p, "kind", ""), "approval")

def Dlg.tool(+p: J.Json) -> String:
  J.Json.get_str(p, "tool", "tool")

def Dlg.detail(+p: J.Json) -> String:
  J.Json.get_str(p, "detail", "")

def Dlg.options(+p: J.Json) -> String:
  J.Json.get_str(p, "options", "")

def Dlg.id(+o: J.Json) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.get(o, "id"), J.Null{})

# the person allowed it (once or for the session)
def Dlg.allows(+answer: String) -> Bool:
  Bool.or(String.eq(answer, "accept"), String.eq(answer, "session"))

# a yes-or-no question's answer
def Dlg.yes(+answer: String) -> Bool:
  Bool.or(Bool.or(String.eq(answer, "Yes"), String.eq(answer, "yes")), Dlg.allows(answer))

# Pi: the extension's dialog resolves (extension_ui_response); an empty
# answer (dismissed) cancels it
def Dlg.pi.line(id: J.Json, kv: J.KV) -> String:
  J.Json.show(J.Json.obj([J.KV{"type", J.Str{"extension_ui_response"}}, J.KV{"id", id}, kv]))

def Dlg.pi.question(empty: Bool, yn: Bool, id: J.Json, +answer: String) -> String:
  match empty yn:
    case True{} _:
      Dlg.pi.line(id, J.KV{"cancelled", J.Flag{True{}}})
    case False{} True{}:
      Dlg.pi.line(id, J.KV{"confirmed", J.Flag{Dlg.yes(answer)}})
    case False{} False{}:
      Dlg.pi.line(id, J.KV{"value", J.Str{answer}})

# the label an approval's answer picks: allow for the session (else once),
# allow once, or deny
def Dlg.label(+p: J.Json, +answer: String) -> String:
  Bool.pick(String, String.eq(answer, "session"), Dlg.or(J.Json.get_str(p, "session", ""), J.Json.get_str(p, "once", "")),
    Bool.pick(String, String.eq(answer, "accept"), J.Json.get_str(p, "once", ""), J.Json.get_str(p, "deny", "Deny")))

# an approval Pi's extension asked as a confirm: yes or no; one Oh My Pi
# asked as a select (its choices in once, session, deny): the label the
# answer picks
def Dlg.pi.approval(confirm: Bool, +p: J.Json, id: J.Json, +answer: String) -> String:
  match confirm:
    case True{}:
      Dlg.pi.line(id, J.KV{"confirmed", J.Flag{Dlg.allows(answer)}})
    case False{}:
      Dlg.pi.line(id, J.KV{"value", J.Str{Dlg.label(p, answer)}})

def Dlg.pi(approval: Bool, +p: J.Json, id: J.Json, +answer: String) -> String:
  match approval:
    case True{}:
      Dlg.pi.approval(String.is_empty(J.Json.get_str(p, "once", "")), p, id, answer)
    case False{}:
      Dlg.pi.question(String.is_empty(answer), J.Json.get_bool(p, "bool", False{}), id, answer)

# ACP elicitation: accepted with the field's value, or cancelled
def Dlg.result(id: J.Json, r: J.Json) -> String:
  J.Json.show(J.Json.obj([J.KV{"jsonrpc", J.Str{"2.0"}}, J.KV{"id", id}, J.KV{"result", r}]))

def Dlg.accept(+key: String, v: J.Json) -> J.Json:
  J.Json.obj([J.KV{"action", J.Str{"accept"}}, J.KV{"content", J.Json.obj([J.KV{key, v}])}])

def Dlg.elicit.question(empty: Bool, yn: Bool, +p: J.Json, id: J.Json, +answer: String) -> String:
  match empty yn:
    case True{} _:
      Dlg.result(id, J.Json.obj([J.KV{"action", J.Str{"cancel"}}]))
    case False{} True{}:
      Dlg.result(id, Dlg.accept(J.Json.get_str(p, "key", "value"), J.Flag{Dlg.yes(answer)}))
    case False{} False{}:
      Dlg.result(id, Dlg.accept(J.Json.get_str(p, "key", "value"), J.Str{answer}))

def Dlg.elicit(approval: Bool, +p: J.Json, id: J.Json, +answer: String) -> String:
  match approval:
    case True{}:
      Dlg.result(id, Dlg.accept(J.Json.get_str(p, "key", "value"), J.Str{Dlg.label(p, answer)}))
    case False{}:
      Dlg.elicit.question(String.is_empty(answer), J.Json.get_bool(p, "bool", False{}), p, id, answer)

def Dlg.reply.k(pi: Bool, +o: J.Json, +answer: String) -> String:
  match pi:
    case True{}:
      Dlg.pi(Dlg.approval(J.Json.get_obj(o, "params")), J.Json.get_obj(o, "params"), Dlg.id(o), answer)
    case False{}:
      Dlg.elicit(Dlg.approval(J.Json.get_obj(o, "params")), J.Json.get_obj(o, "params"), Dlg.id(o), answer)

def Dlg.reply.o(+o: J.Json, +answer: String) -> String:
  Dlg.reply.k(String.eq(J.Json.get_str(J.Json.get_obj(o, "params"), "proto", ""), "pi"), o, answer)

# the agent's line for a parked envelope, once the person answered
# ("accept", "session", anything else declines; a question's answer is
# its text, "" when dismissed)
def Dlg.reply(+body: String, +answer: String) -> String:
  Dlg.reply.o(Maybe.default(&2, J.Json, J.Json.parse(body), J.Null{}), answer)
