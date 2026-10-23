import Base
import ./check.bend as C
import ../src/server/thin-actor.bend as A
import ../src/server/thin-view.bend as V
import ../src/core/client.bend as U
import ../src/core/model.bend as M
import ../src/core/json.bend as J
import ../src/core/vt.bend as VT

def obj(text: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{})

def request(+action: String, value: String, owner: String) -> J.Json:
  J.Json.obj([J.KV{"terminalInput", J.Flag{True{}}}, J.KV{"terminalOwner", J.Str{owner}}, J.KV{"action", J.Str{action}}, J.KV{"value", J.Str{value}}, J.KV{"target", V.Target.json("thread", "a")}])

def ui() -> U.Ui:
  +st = M.State.apply(M.State.empty(), M.ThreadCreated{"a", "", "Terminal", M.Local{}, "", "/tmp", "codex", "", 1n})
  +p = obj("{\"target\":{\"kind\":\"thread\",\"id\":\"a\"},\"session\":{\"sel\":\"a\",\"rid\":100,\"drafts\":{},\"open\":{},\"info\":{}}}")
  U.Ui.scratch_set(U.Ui.flag_on(V.Session.current(True{}, st, obj("{}"), obj("{}"), 1n, p), "term"), "@terminal.owner", "a")

def bytes(a: V.ActResult) -> String:
  match a:
    case V.ActResult{_, c <> _}: J.Json.show(J.Json.get_obj(J.Json.get_obj(A.Actor.rpc(c), "p"), "b"))
    case _: "no command"

def count(a: V.ActResult) -> Nat:
  match a:
    case V.ActResult{_, cs}: List.length(&2, J.Json, cs)

def main() -> IO(Unit):
  do IO<Unit>:
    +u : U.Ui = ui()
    +p : J.Json = request("term-key", "`\t0", "a")
    C.Check.str("web exact input opt-in", Bool.show(A.TerminalInput.request(True{}, p)), "True")
    C.Check.str("mobile keeps full shape", Bool.show(A.TerminalInput.request(False{}, p)), "False")
    C.Check.str("default request keeps full shape", Bool.show(A.TerminalInput.request(True{}, obj("{\"action\":\"term-key\"}"))), "False")
    C.Check.str("toggle never opts in", Bool.show(A.TerminalInput.request(True{}, request("term-toggle", "", "a"))), "False")
    C.Check.str("retained owner required", Bool.show(A.TerminalInput.owner(u, request("term-key", "a\t0", "b"))), "False")
    C.Check.str("hidden terminal refuses input", Bool.show(A.TerminalInput.owner(U.Ui.flag_off(u, "term"), p)), "False")
    +literal : V.ActResult = A.TerminalInput.run(True{}, True{}, True{}, u, p, 1n)
    C.Check.str("Bend still encodes literal backtick", bytes(literal), "[96]")
    C.Check.str("normal actor command qualifies", Bool.show(A.TerminalInput.allowed(True{}, p, literal)), "True")
    C.Check.str("stale captured owner issues nothing", Nat.show(count(A.TerminalInput.run(True{}, False{}, True{}, u, request("term-key", "a\t0", "b"), 1n))), "0")
    C.Check.str("Bend still encodes CtrlC", bytes(A.TerminalInput.run(True{}, True{}, True{}, u, request("term-key", "c\t4", "a"), 1n)), "[3]")
    +app : U.Ui = U.Ui.term_set(u, "a", VT.Vt.feed(VT.Vt.new(80, 24), [27, 91, 63, 49, 104]))
    C.Check.str("authoritative application cursor mode retained", bytes(A.TerminalInput.run(True{}, True{}, True{}, app, request("term-key", "ArrowUp\t0", "a"), 1n)), "[27,79,65]")
    +result : J.Json = A.TerminalInput.result(literal)
    C.Check.str("ACK contains no rendered picture", Bool.show(Maybe.is_some(&2, J.Json, J.Json.get(result, "shown"))), "False")
    C.Check.str("ACK contains no page window", Bool.show(Maybe.is_some(&2, J.Json, J.Json.get(result, "window"))), "False")
    C.Check.str("ACK retains exact terminal owner", J.Json.get_str(result, "terminalOwner", ""), "a")
