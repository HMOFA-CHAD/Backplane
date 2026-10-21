import Base
import ../src/server/desktop-broker.bend as B
import ../src/core/desktop-browser.bend as D
import ../src/core/json.bend as J
import ./desktop_broker_test.bend as F

def check(name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.print("ok " ++ name)
    case False{}: IO.die(Unit, 1, "FAIL " ++ name)

def read(out: Chan(String)) -> IO(J.Json):
  do IO<J.Json>:
    m : Maybe<&1, String> <- Chan.recv(String, out)
    return F.obj(Maybe.default(&1, String, m, ""))

def main() -> IO(Unit):
  do IO<Unit>:
    +out : Chan(String) <- Chan.new(String, 128)
    +b : B.Broker = F.state(out)
    +own : B.Broker = B.Broker.document_save(b, F.event())
    +notTerminal : B.Broker = B.Broker.set_target(own, D.Desktop.put(B.Broker.target(own, "A"), "ready", J.Flag{False{}}))
    check("own main ready admits firstscript before terminal ready", B.Broker.record_valid(notTerminal, F.record(), F.event()))
    check("without own main document proof firstscript refused", Bool.not(B.Broker.record_valid(B.Broker.set_target(b, D.Desktop.put(B.Broker.target(b, "A"), "ready", J.Flag{False{}})), F.record(), F.event())))
    +mutation : B.Broker = B.Broker.bump_owner(notTerminal, "A")
    check("mutation permission bumps independently", Nat.is_eq(J.Json.get_nat(B.Broker.owner(mutation, "A"), "revision", 0n), 8n))
    check("mutation bump preserves canonical capture revision", Nat.is_eq(B.Broker.capture_revision(mutation, "A"), 7n))
    check("old live capture survives expected mutation revision", B.Broker.record_valid(mutation, F.record(), F.event()))
    +nextTarget : J.Json = D.Desktop.put(F.target(), "generation", J.Num{"3"})
    +next : B.Broker <- B.Broker.event(own, J.Json.obj([J.KV{"owner", J.Str{"A"}}, J.KV{"target", nextTarget}, J.KV{"grantRevision", J.Num{"7"}}]), "generation-A")
    check("navigation does not issue terminal readiness", Bool.not(J.Json.get_bool(B.Broker.target(next, "A"), "ready", True{})))
    check("same-WC navigation preserves capture lineage", Nat.is_eq(B.Broker.capture_revision(next, "A"), 7n))
    check("old-generation document cannot record after navigation", Bool.not(B.Broker.record_valid(next, F.record(), F.event())))
    +nextEvent : J.Json = D.Desktop.put(D.Desktop.put(F.event(), "generation", J.Num{"3"}), "document", D.Desktop.put(F.document(), "documentNonce", J.Str{"new-main-document"}))
    +nextProof : B.Broker <- B.Broker.document_ready(True{}, next, nextEvent, "next-ready")
    +nextRecord : J.Json = D.Desktop.put(F.record(), "event", nextEvent)
    check("new own proof permits firstscript before load completion", B.Broker.record_valid(nextProof, nextRecord, nextEvent))
    check("old nonce cannot borrow new own document proof", Bool.not(B.Broker.record_valid(nextProof, nextRecord, D.Desktop.put(nextEvent, "document", F.document()))))
    check("mutation revision is never accepted as capture authority", Bool.not(B.Broker.record_valid(nextProof, D.Desktop.put(nextRecord, "captureRevision", J.Num{"8"}), nextEvent)))
    +off : B.Broker = B.Broker.policy(nextProof, "A", True{}, "agent", False{})
    check("canonical Teach stop increments capture lineage", Nat.is_eq(B.Broker.capture_revision(off, "A"), 8n))
    check("Teach stop refuses current old capture", Bool.not(B.Broker.record_valid(off, nextRecord, nextEvent)))
    +back : B.Broker = B.Broker.policy(off, "A", True{}, "agent", True{})
    check("recording restored cannot revive old capture revision", Bool.not(B.Broker.record_valid(back, nextRecord, nextEvent)))
    check("installed proof survives policy change", B.Broker.main_document_ready(J.Json.get_obj(B.Broker.meta(back), "documents"), back, nextTarget))
    +unknown : B.Broker = B.Broker.latch_unknown(nextProof, "A")
    check("UNKNOWN advances and disables capture", Bool.and(Nat.is_eq(B.Broker.capture_revision(unknown, "A"), 8n), Bool.not(B.Broker.record_valid(unknown, nextRecord, nextEvent))))
    +retired : B.Broker = B.Broker.set_target(nextProof, D.Desktop.put(B.Broker.target(nextProof, "A"), "retired", J.Flag{True{}}))
    check("retired target cannot retain capture through installed proof", Bool.not(B.Broker.record_valid(retired, nextRecord, nextEvent)))
    +rout : Chan(String) <- Chan.new(String, 8)
    +rb : B.Broker = B.Broker.bump_owner(F.state(rout), "A")
    B.Broker.revoke(rb, "A")
    +mutationRevoke : J.Json <- read(rout)
    check("lifecycle mutation revocation explicitly scoped", String.eq(J.Json.get_str(J.Json.get_obj(mutationRevoke, "payload"), "scope", ""), "mutation"))
    B.Broker.revoke_all(rb, "A")
    +fullRevoke : J.Json <- read(rout)
    check("canonical revocation explicitly covers both domains", String.eq(J.Json.get_str(J.Json.get_obj(fullRevoke, "payload"), "scope", ""), "all"))
    check("full revocation carries distinct mutation floor", Nat.is_eq(J.Json.get_nat(J.Json.get_obj(fullRevoke, "payload"), "revision", 0n), 8n))
    check("full revocation carries distinct capture floor", Nat.is_eq(J.Json.get_nat(J.Json.get_obj(fullRevoke, "payload"), "captureRevision", 0n), 7n))
    +events : Chan(String) <- Chan.new(String, 4)
    +queued : B.Broker <- B.Broker.record(True{}, nextProof, nextRecord, events, "firstscript-candidate")
    +candidate : J.Json <- read(events)
    check("queued firstscript candidate valid before policy transition", B.Broker.capture_commit_valid(queued, candidate))
    check("canonical policy transition refuses queued old capture at commit", Bool.not(B.Broker.capture_commit_valid(B.Broker.policy(queued, "A", True{}, "agent", False{}), candidate)))
    Chan.close(String, out)
    Chan.close(String, rout)
    Chan.close(String, events)
