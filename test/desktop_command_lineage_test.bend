import Base
import ../src/server/desktop-broker.bend as B
import ../src/core/desktop-browser.bend as D
import ../src/core/json.bend as J
import ./desktop_broker_test.bend as F

def check(name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.print("ok " ++ name)
    case False{}: IO.die(Unit, 1, "FAIL " ++ name)

def initial(+out: Chan(String), reply: Chan(String), op: String) -> B.Broker:
  B.Broker.replace_pending(B.Broker.command_put(F.state(out), "command-A", B.Broker.command_initial("A", F.target(), 7n, op, F.obj("{}"))), [B.Pending{"command-A", "A", F.target(), 7n, reply}])

def next_target() -> J.Json:
  D.Desktop.put(F.target(), "generation", J.Num{"3"})

def generation() -> J.Json:
  J.Json.obj([J.KV{"owner", J.Str{"A"}}, J.KV{"target", next_target()}, J.KV{"fromTarget", F.target()}, J.KV{"grantRevision", J.Num{"7"}}, J.KV{"dispatchId", J.Str{"command-A"}}, J.KV{"dispatchRevision", J.Num{"7"}}])

def final_result() -> J.Json:
  J.Json.obj([J.KV{"owner", J.Str{"A"}}, J.KV{"target", next_target()}, J.KV{"dispatchTarget", F.target()}, J.KV{"grantRevision", J.Num{"7"}}, J.KV{"resultRevision", J.Num{"8"}}, J.KV{"reply", F.obj("{\"ok\":true,\"result\":\"completed\"}")}])

def main() -> IO(Unit):
  do IO<Unit>:
    +out : Chan(String) <- Chan.new(String, 128)
    +reply : Chan(String) <- Chan.new(String, 16)
    +events : Chan(String) <- Chan.new(String, 8)
    +b : B.Broker = initial(out, reply, "navigate")
    +command : J.Json = B.Broker.command(b, "command-A")
    check("navigation explicitly classified by original op", J.Json.get_bool(command, "navigates", False{}))
    check("correlated navigation transition validates original fence", B.Broker.command_transition_valid(b, generation(), command))
    check("new mutation grant cannot replace original dispatch revision", Bool.not(B.Broker.command_transition_valid(b, D.Desktop.put(generation(), "dispatchRevision", J.Num{"8"}), command)))
    check("foreign previous tab cannot advance outcome", Bool.not(B.Broker.command_transition_valid(b, D.Desktop.put(generation(), "fromTarget", D.Desktop.put(F.target(), "tabId", J.Str{"foreign"})), command)))
    +changed : B.Broker = B.Broker.policy(b, "A", True{}, "person", True{})
    +restored : B.Broker = B.Broker.policy(changed, "A", True{}, "agent", True{})
    check("changed and restored policy cannot revive original dispatch", Bool.not(B.Broker.command_transition_valid(restored, generation(), B.Broker.command(restored, "command-A"))))
    +n : B.Broker <- B.Broker.event(b, generation(), "generation-event")
    check("navigation preserves immutable original target", D.Target.eq(D.Target.decode(J.Json.get_obj(B.Broker.command(n, "command-A"), "originalTarget")), D.Target.decode(F.target())))
    check("navigation preserves immutable original revision", Nat.is_eq(J.Json.get_nat(B.Broker.command(n, "command-A"), "originalRevision", 0n), 7n))
    check("outcome revision advances separately", Nat.is_eq(J.Json.get_nat(B.Broker.command(n, "command-A"), "expectedRevision", 0n), 8n))
    check("navigation result waits for current terminal ready", Bool.not(B.Broker.result_valid_request(n, "command-A", "A", F.target(), 7n, final_result())))
    +ready : B.Broker = B.Broker.set_target(n, D.Desktop.put(B.Broker.target(n, "A"), "ready", J.Flag{True{}}))
    check("final own target and acknowledged result revision accepted", B.Broker.result_valid_request(ready, "command-A", "A", F.target(), 7n, final_result()))
    check("result cannot relabel original dispatch target", Bool.not(B.Broker.result_valid_request(ready, "command-A", "A", F.target(), 7n, D.Desktop.put(final_result(), "dispatchTarget", next_target()))))
    check("result cannot borrow final revision as original authority", Bool.not(B.Broker.result_valid_request(ready, "command-A", "A", F.target(), 7n, D.Desktop.put(final_result(), "grantRevision", J.Num{"8"}))))
    check("wrong final generation refuses even with same tab", Bool.not(B.Broker.result_valid_request(ready, "command-A", "A", F.target(), 7n, D.Desktop.put(final_result(), "target", D.Desktop.put(next_target(), "generation", J.Num{"4"})))))
    +unsolicited : B.Broker <- B.Broker.event(b, D.Desktop.put(generation(), "dispatchId", J.Str{"other-command"}), "unsolicited-event")
    check("unrelated navigation cannot complete pending command", Bool.not(J.Json.get_bool(B.Broker.command(unsolicited, "command-A"), "valid", True{})))
    +snapshot : B.Broker = initial(out, reply, "snapshot")
    check("non-navigation op cannot adopt navigation outcome", Bool.not(B.Broker.command_transition_valid(snapshot, generation(), B.Broker.command(snapshot, "command-A"))))
    +malformed : J.Json = D.Desktop.put(final_result(), "dispatchTarget", D.Desktop.put(F.target(), "tabId", J.Str{"foreign"}))
    +checked : J.Json = B.Broker.checked_result(B.Broker.pending(ready), ready, "command-A", malformed)
    check("malformed successful reply classified UNKNOWN", B.Broker.result_unknown(checked))
    +settled : B.Broker <- B.Broker.frame_op("result", ready, J.Json.obj([J.KV{"id", J.Str{"command-A"}}, J.KV{"payload", D.Desktop.put(malformed, "owner", J.Str{"B"})}]), "B", "version", events)
    check("bad result latches original pending owner", B.Broker.unknown_owner(settled, "A"))
    check("bad result cannot latch supplied foreign owner", Bool.not(B.Broker.unknown_owner(settled, "B")))
    check("settled command metadata removed", String.is_empty(J.Json.get_str(B.Broker.command(settled, "command-A"), "owner", "")))
    +refusal : J.Json = J.Json.obj([J.KV{"target", F.target()}, J.KV{"dispatchTarget", F.target()}, J.KV{"grantRevision", J.Num{"7"}}, J.KV{"resultRevision", J.Num{"7"}}, J.KV{"reply", F.obj("{\"ok\":false,\"dispatched\":false}")}])
    check("exact known predispatch refusal remains known after policy change", B.Broker.result_valid_request(changed, "command-A", "A", F.target(), 7n, refusal))
    +reload : B.Broker = initial(out, reply, "reload")
    +receipt : J.Json = D.Desktop.put(refusal, "reply", J.Json.obj([J.KV{"ok", J.Flag{True{}}}, J.KV{"result", J.Json.obj([J.KV{"target", F.target()}, J.KV{"action", J.Str{"reload"}}, J.KV{"dispatched", J.Flag{True{}}}, J.KV{"loadComplete", J.Flag{False{}}}])}]))
    check("native dispatch receipt does not claim later load completion", B.Broker.result_valid_request(reload, "command-A", "A", F.target(), 7n, receipt))
    check("ordinary navigation cannot forge native history receipt", Bool.not(B.Broker.command_dispatch_receipt(b, "A", receipt, command)))
    Chan.close(String, out)
    Chan.close(String, reply)
    Chan.close(String, events)
