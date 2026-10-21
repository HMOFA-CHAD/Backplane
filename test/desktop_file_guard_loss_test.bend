import Base
import ../src/server/desktop-broker.bend as B
import ../src/core/desktop-browser.bend as D
import ../src/core/json.bend as J
import ./desktop_broker_test.bend as F
import ./desktop_registry_close_test.bend as R
import ./desktop_preparation_test.bend as P

def check(name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.print("ok " ++ name)
    case False{}: IO.die(Unit, 1, "FAIL " ++ name)

def loss() -> J.Json:
  J.Json.obj([J.KV{"event", D.Desktop.put(F.target(), "type", J.Str{"file-guard-lost"})}])

def ready() -> J.Json:
  J.Json.obj([J.KV{"target", F.target()}, J.KV{"recorderReady", J.Flag{True{}}}, J.KV{"recorderSourceSha256", J.Str{"2e4b03765cc4ae6595e32048555ffe27e750994a85c18b89027064f3c0c15350"}}, J.KV{"document", F.document()}])

def main() -> IO(Unit):
  do IO<Unit>:
    +out : Chan(String) <- Chan.new(String, 128)
    +reply : Chan(String) <- Chan.new(String, 8)
    +q : Chan(B.Message) <- Chan.new(B.Message, 8)
    +events : Chan(String) <- Chan.new(String, 8)
    +b : B.Broker = B.Broker.document_save(R.base(out), F.event())
    check("exact registered root loss accepted", B.Broker.guard_lost_valid(b, loss()))
    check("foreign root cannot lose another owner guard", Bool.not(B.Broker.guard_lost_valid(b, D.Desktop.put(loss(), "event", D.Desktop.put(J.Json.get_obj(loss(), "event"), "owner", J.Str{"B"})))))
    check("stale generation cannot revoke current root", Bool.not(B.Broker.guard_lost_valid(b, D.Desktop.put(loss(), "event", D.Desktop.put(J.Json.get_obj(loss(), "event"), "generation", J.Num{"1"})))))
    check("arbitrary event cannot revoke file guard", Bool.not(B.Broker.guard_lost_valid(b, D.Desktop.put(loss(), "event", D.Desktop.put(J.Json.get_obj(loss(), "event"), "type", J.Str{"ready"})))))
    +lost : B.Broker <- B.Broker.frame_op("guest.guard-lost", b, J.Json.obj([J.KV{"id", J.Str{"loss-event"}}, J.KV{"payload", loss()}]), "A", "version", events)
    +revoke : J.Json <- P.read(out)
    check("loss revokes both permission domains", String.eq(J.Json.get_str(J.Json.get_obj(revoke, "payload"), "scope", ""), "all"))
    P.drain(5n, out)
    +ack : J.Json <- P.read(out)
    check("loss ACK correlated to private event", String.eq(J.Json.get_str(ack, "id", ""), "loss-event"))
    check("loss ACK has actual new permission revision", Nat.is_eq(J.Json.get_nat(J.Json.get_obj(ack, "payload"), "grantRevision", 0n), 8n))
    check("passive guard loss is not an unknown dispatched operation", Bool.not(B.Broker.unknown_owner(lost, "A")))
    check("affected root becomes not ready", Bool.not(J.Json.get_bool(B.Broker.target(lost, "A"), "ready", True{})))
    check("affected root latches mandatory guard loss", B.Broker.target_guard_lost(lost, F.target()))
    check("guard loss does not claim actual native exit", Bool.not(J.Json.get_bool(B.Broker.target(lost, "A"), "retired", False{})))
    check("hidden root still consumes actual live capacity", Nat.is_eq(B.Broker.target_count(J.Json.get_obj(B.Broker.meta(lost), "targets"), "A", False{}), 2n))
    check("other root keeps its own guard state", Bool.not(B.Broker.target_guard_lost(lost, R.second())))
    check("guard loss bumps capture independently", Nat.is_eq(B.Broker.capture_revision(lost, "A"), 8n))
    +safety : J.Json = B.Broker.target_payload(lost, "A")
    check("guard-lost root retains only three safety operations", Nat.is_eq(List.length(&2, J.Json, J.Json.elems(J.Json.get_obj(safety, "operations"))), 3n))
    check("guard-lost root has no CDP methods", Nat.is_eq(List.length(&2, J.Json, J.Json.elems(J.Json.get_obj(safety, "cdpMethods"))), 0n))
    check("guard-lost root has no trusted reinitialization", Nat.is_eq(List.length(&2, J.Json, J.Json.elems(J.Json.get_obj(safety, "initializationMethods"))), 0n))
    check("later ready cannot repair same root", Bool.not(B.Broker.ready_valid(lost, ready())))
    check("next generation cannot reattach same root", Bool.not(B.Broker.generation_valid(lost, J.Json.obj([J.KV{"target", D.Desktop.put(F.target(), "generation", J.Num{"3"})}, J.KV{"grantRevision", J.Num{"8"}}]))))
    check("current capture revision cannot bypass lost guard", Bool.not(B.Broker.record_valid(lost, D.Desktop.put(F.record(), "captureRevision", J.Num{"8"}), F.event())))
    check("repeated loss cannot mint revisions", Bool.not(B.Broker.guard_lost_valid(lost, loss())))
    +restored : B.Broker = B.Broker.policy(B.Broker.policy(lost, "A", True{}, "person", False{}), "A", True{}, "agent", True{})
    check("policy labels cannot reinstall mandatory guard", B.Broker.target_guard_lost(restored, F.target()))
    +refused : B.Broker <- B.Broker.call(lost, q, "navigate", F.obj("{\"page\":\"A\",\"url\":\"https://example.invalid/\"}"), reply)
    +noAction : J.Json <- P.read(reply)
    check("unusable existing root has no automatic replacement", Bool.not(J.Json.get_bool(noAction, "dispatched", True{})))
    check("guard refusal creates no preparation", Bool.not(B.Broker.preparing(refused, "A")))
    check("known root safety close remains addressable", B.Broker.request_target_valid(lost, "close_page", F.obj("{\"page\":\"A\"}")))
    +closedCommand : B.Broker <- B.Broker.call(lost, q, "close_page", F.obj("{\"page\":\"A\"}"), reply)
    +closeCall : J.Json <- P.read(out)
    check("safety close dispatches exact affected root", D.Target.eq(D.Target.decode(J.Json.get_obj(J.Json.get_obj(closeCall, "payload"), "target")), D.Target.decode(F.target())))
    check("safety close is tracked as actual pending command", B.Broker.owner_has_dispatch(B.Broker.pending(closedCommand), "A"))
    +ordinary : B.Broker = R.pending(b, "running", F.target(), "click", F.obj("{}"), reply)
    +unknown : B.Broker = B.Broker.guard_lost_apply(ordinary, loss())
    check("guard loss during original call latches UNKNOWN", B.Broker.unknown_owner(unknown, "A"))
    check("new canonical grant cannot clear unresolved command", B.Broker.unknown_owner(B.Broker.policy(unknown, "A", True{}, "agent", True{}), "A"))
    +preparing : B.Broker = B.Broker.replace_pending(B.Broker.preparation_put(b, "A", F.obj("{\"prepareId\":\"p\",\"createId\":\"c\",\"valid\":true,\"revision\":7}")), [B.Pending{"p", "A", F.obj("{\"preparation\":true}"), 7n, reply}])
    +setupLoss : B.Broker = B.Broker.guard_lost_apply(preparing, loss())
    check("initial guard failure is not a user dispatch", Bool.not(B.Broker.unknown_owner(setupLoss, "A")))
    check("initial guard loss invalidates preparation authority", Bool.not(B.Broker.preparation_current(setupLoss, "A")))
    check("failed setup remains eligible for exact cleanup", B.Broker.prepare_failed_valid(setupLoss, F.obj("{\"owner\":\"A\",\"phase\":\"preparation\",\"prepareId\":\"p\",\"createId\":\"c\"}")))
    check("actual later closed event still recognized", B.Broker.closed_valid(lost, D.Desktop.put(F.target(), "type", J.Str{"closed"})))
