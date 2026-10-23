import Base
import ./check.bend as C
import ./desktop_broker_test.bend as F
import ./desktop_command_lineage_test.bend as L
import ../src/server/desktop-broker.bend as B
import ../src/core/desktop-browser.bend as D
import ../src/core/json.bend as J

# New finite-receipt outcome cases only. Original dispatch authority stays
# immutable; the sole integrator runs this focused test before the candidate.
def receipt() -> J.Json:
  D.Desktop.put(L.final_result(), "reply", J.Json.obj([J.KV{"ok", J.Flag{True{}}}, J.KV{"result", J.Json.obj([
    J.KV{"target", F.target()}, J.KV{"action", J.Str{"back"}}, J.KV{"dispatched", J.Flag{True{}}}, J.KV{"loadComplete", J.Flag{False{}}}])}]))

def valid(+b: B.Broker, +p: J.Json) -> Bool:
  B.Broker.result_valid_request(b, "command-A", "A", F.target(), 7n, p)

def reply_result(+p: J.Json, +key: String, value: J.Json) -> J.Json:
  D.Desktop.put(p, "reply", D.Desktop.put(J.Json.get_obj(p, "reply"), "result", D.Desktop.put(J.Json.get_obj(J.Json.get_obj(p, "reply"), "result"), key, value)))

def check(name: String, ok: Bool) -> IO(Unit):
  C.Check.str(name, Bool.show(ok), "True")

def main() -> IO(Unit):
  do IO<Unit>:
    +out : Chan(String) <- Chan.new(String, 128)
    +reply : Chan(String) <- Chan.new(String, 16)
    +before : B.Broker = L.initial(out, reply, "back")
    +after : B.Broker <- B.Broker.event(before, L.generation(), "generation-event")
    check("correlated Back dispatch receipt accepted before new document readiness", valid(after, receipt()))
    check("ordinary command results still require document readiness", Bool.not(B.Broker.command_result_current_live(after, "A", receipt(), B.Broker.command(after, "command-A"))))
    check("receipt cannot rewrite original dispatch target or revision", Bool.and(
      Bool.not(valid(after, D.Desktop.put(receipt(), "dispatchTarget", L.next_target()))),
      Bool.not(valid(after, D.Desktop.put(receipt(), "grantRevision", J.Num{"8"})))))
    check("receipt outcome must match acknowledged generation and revision", Bool.and(
      Bool.not(valid(after, D.Desktop.put(receipt(), "target", F.target()))),
      Bool.not(valid(after, D.Desktop.put(receipt(), "resultRevision", J.Num{"7"})))))
    +unrelated : B.Broker <- B.Broker.event(before, D.Desktop.put(L.generation(), "dispatchId", J.Str{"another-command"}), "unrelated-event")
    check("uncorrelated generation cannot authorize dispatch receipt", Bool.not(valid(unrelated, receipt())))
    check("later policy revision cannot supply outcome authority", Bool.not(valid(B.Broker.policy(after, "A", True{}, "person", False{}), receipt())))
    check("retired or differently selected native root cannot settle receipt", Bool.and(
      Bool.not(valid(B.Broker.set_target(after, D.Desktop.put(B.Broker.target(after, "A"), "retired", J.Flag{True{}})), receipt())),
      Bool.not(valid(B.Broker.set_owner(after, "A", D.Desktop.put(B.Broker.owner(after, "A"), "activeTabId", J.Str{"different-tab"})), receipt()))))
    check("UNKNOWN owner cannot settle successful native receipt", Bool.not(valid(B.Broker.latch_unknown(after, "A"), receipt())))
    check("receipt retains original native target and never claims load complete", Bool.and(
      Bool.not(valid(after, reply_result(receipt(), "target", L.next_target()))),
      Bool.not(valid(after, reply_result(receipt(), "loadComplete", J.Flag{True{}})))))
    +navigation : B.Broker <- B.Broker.event(L.initial(out, reply, "navigate"), L.generation(), "navigation-event")
    check("ordinary navigation cannot use finite native Back receipt", Bool.not(valid(navigation, receipt())))
    Chan.close(String, out)
    Chan.close(String, reply)
