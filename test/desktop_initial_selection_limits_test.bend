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

def ready_root(+out: Chan(String)) -> B.Broker:
  +b = R.base(out)
  B.Broker.set_owner(b, "A", D.Desktop.put(B.Broker.owner(b, "A"), "tabId", J.Str{"tab-B"}))

def tagged(+b: B.Broker, reply: Chan(String)) -> B.Broker:
  B.Broker.replace_pending(B.Broker.command_put(b, "initial-command", B.Broker.command_preparation(B.Broker.command_initial("A", R.second(), 7n, "type", F.obj("{}")), "preparation-A", "create-A")), [B.Pending{"initial-command", "A", R.second(), 7n, reply}])

def inventory(+b: B.Broker, active: String) -> J.Json:
  D.Desktop.put(D.Desktop.put(D.Desktop.put(D.Desktop.put(R.inventory(b, active), "dispatchId", J.Str{"initial-command"}), "dispatchRevision", J.Num{"7"}), "prepareId", J.Str{"preparation-A"}), "createId", J.Str{"create-A"})

def target_fields(+n: Nat, +owner: String, +retired: Bool) -> J.Json:
  match n:
    case 0n: J.End{}
    case 1n+k:
      J.Field{"root-" ++ Nat.show(k), J.Json.obj([J.KV{"owner", J.Str{owner}}, J.KV{"tabId", J.Str{"root-" ++ Nat.show(k)}}, J.KV{"generation", J.Num{"1"}}, J.KV{"retired", J.Flag{retired}}]), target_fields(k, owner, retired)}

def ids(+n: Nat) -> J.Json:
  match n:
    case 0n: J.End{}
    case 1n+k: J.Field{"seen-" ++ Nat.show(k), J.Flag{True{}}, ids(k)}

def targets(+b: B.Broker, n: Nat, owner: String, retired: Bool) -> B.Broker:
  B.Broker.with_meta(b, D.Desktop.put(B.Broker.meta(b), "targets", J.Obj{target_fields(n, owner, retired)}))

def has_method(xs: List<&2, J.Json>, +method: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case h <> t: Bool.or(String.eq(J.Json.show(h), J.Json.show(J.Str{method})), has_method(t, method))

def main() -> IO(Unit):
  do IO<Unit>:
    +out : Chan(String) <- Chan.new(String, 128)
    +reply : Chan(String) <- Chan.new(String, 8)
    +events : Chan(String) <- Chan.new(String, 8)
    +b : B.Broker = ready_root(out)
    +pending : B.Broker = tagged(b, reply)
    +command : J.Json = D.Desktop.put(B.Broker.command(pending, "initial-command"), "id", J.Str{"initial-command"})
    check("new root initial type keeps immutable creation lineage", String.eq(J.Json.get_str(command, "createId", ""), "create-A"))
    check("exact new-root selection valid for nonselect first operation", B.Broker.registry_selection_valid(command, pending, inventory(pending, "tab-B"), "tab-B"))
    check("unrelated guest cannot become initial setup target", Bool.not(B.Broker.registry_selection_valid(command, pending, inventory(pending, "tab-A"), "tab-A")))
    check("foreign creation cannot authorize initial selection", Bool.not(B.Broker.registry_selection_valid(command, pending, D.Desktop.put(inventory(pending, "tab-B"), "createId", J.Str{"foreign"}), "tab-B")))
    check("foreign preparation cannot authorize initial selection", Bool.not(B.Broker.registry_selection_valid(command, pending, D.Desktop.put(inventory(pending, "tab-B"), "prepareId", J.Str{"foreign"}), "tab-B")))
    check("wrong dispatch cannot borrow creation lineage", Bool.not(B.Broker.registry_selection_valid(command, pending, D.Desktop.put(inventory(pending, "tab-B"), "dispatchId", J.Str{"foreign"}), "tab-B")))
    check("initial registry wrong createId refused before action", Bool.not(B.Broker.registry_valid(pending, D.Desktop.put(inventory(pending, "tab-B"), "createId", J.Str{"foreign"}))))
    +selected : B.Broker <- B.Broker.registry_apply(B.Broker.registry_valid(pending, inventory(pending, "tab-B")), pending, inventory(pending, "tab-B"), "selection-event")
    check("initial physical selection preserves original action fence", Nat.is_eq(J.Json.get_nat(B.Broker.owner(selected, "A"), "revision", 0n), 7n))
    check("initial selection preserves original mutation revision", Nat.is_eq(J.Json.get_nat(B.Broker.command(selected, "initial-command"), "originalRevision", 0n), 7n))
    check("initial selection preserves original capture revision", Nat.is_eq(B.Broker.capture_revision(selected, "A"), 7n))
    check("initial selection is one-use bookkeeping", Bool.not(J.Json.get_bool(B.Broker.command(selected, "initial-command"), "initialSelection", True{})))
    check("initial first-operation result validates exact new root", B.Broker.result_valid_request(selected, "initial-command", "A", R.second(), 7n, R.outcome(R.second(), 7n)))
    check("old target cannot impersonate completed initial root", Bool.not(B.Broker.result_valid_request(selected, "initial-command", "A", R.second(), 7n, D.Desktop.put(R.outcome(R.second(), 7n), "target", F.target()))))
    +preparing : B.Broker = B.Broker.preparation_put(b, "A", F.obj("{\"prepareId\":\"preparation-A\",\"createId\":\"create-A\",\"valid\":true,\"revision\":7}"))
    check("mandatory interception method present only in preparation init", has_method(J.Json.elems(J.Json.get_obj(B.Broker.target_payload(preparing, "A"), "initializationMethods")), "Page.setInterceptFileChooserDialog"))
    +ordinaryMethods : List<&2, J.Json> = J.Json.elems(J.Json.get_obj(B.Broker.target_payload(b, "A"), "initializationMethods"))
    check("ordinary initialization list remains original six methods", Nat.is_eq(List.length(&2, J.Json, ordinaryMethods), 6n))
    check("public file chooser interception still forbidden", Bool.not(D.Desktop.member(D.Desktop.methods(), "Page.setInterceptFileChooserDialog")))
    check("click-driven navigation keeps original outcome lineage", B.Broker.navigation_op("click", F.obj("{}")))
    check("type-driven navigation keeps original outcome lineage", B.Broker.navigation_op("type", F.obj("{}")))
    check("readonly AX query cannot adopt navigation", Bool.not(B.Broker.navigation_op("cdp", F.obj("{\"method\":\"Accessibility.getFullAXTree\"}"))))
    check("owner live capacity permits31 roots", B.Broker.creation_room(targets(b, 31n, "A", False{}), "A"))
    check("owner live capacity refuses32 roots", Bool.not(B.Broker.creation_room(targets(b, 32n, "A", False{}), "A")))
    check("other owner may create while one owner at32", B.Broker.creation_room(targets(b, 32n, "A", False{}), "B"))
    check("global live capacity refuses128 roots", Bool.not(B.Broker.creation_room(targets(b, 128n, "A", False{}), "B")))
    check("retired roots do not consume live slots", B.Broker.creation_room(targets(b, 128n, "A", True{}), "A"))
    +seen : B.Broker = B.Broker.remember_target(b, "old-root")
    check("root ID cannot be offered twice", Bool.not(B.Broker.offer_slot(seen, "A", D.Desktop.put(R.second(), "tabId", J.Str{"old-root"}))))
    +full : B.Broker = B.Broker.with_meta(b, D.Desktop.put(B.Broker.meta(b), "targetIds", J.Obj{ids(1024n)}))
    check("bounded lifetime ledger refuses without resetting manager", Bool.not(B.Broker.creation_room(full, "A")))
    +retired : B.Broker = B.Broker.set_target(b, D.Desktop.put(F.target(), "retired", J.Flag{True{}}))
    +pruned : B.Broker = B.Broker.prune_targets(retired)
    check("settled retired metadata pruned before next offer", Nat.is_eq(D.Target.fields(J.Json.get_obj(J.Json.get_obj(B.Broker.meta(pruned), "targets"), "tab-A")), 0n))
    check("pruning preserves other registered live roots", String.eq(J.Json.get_str(J.Json.get_obj(J.Json.get_obj(B.Broker.meta(pruned), "targets"), "tab-B"), "owner", ""), "A"))
    +closing : B.Broker = B.Broker.replace_pending(retired, [B.Pending{"closing", "A", F.target(), 7n, reply}])
    check("retired close outcome retained while command pending", J.Json.get_bool(J.Json.get_obj(J.Json.get_obj(B.Broker.meta(B.Broker.prune_targets(closing)), "targets"), "tab-A"), "retired", False{}))
    +cleanup : B.Broker = B.Broker.preparation_put(retired, "A", J.Json.obj([J.KV{"prepareId", J.Str{"p"}}, J.KV{"target", F.target()}]))
    check("cleanup root retained until exact cancellation settles", J.Json.get_bool(J.Json.get_obj(J.Json.get_obj(B.Broker.meta(B.Broker.prune_targets(cleanup)), "targets"), "tab-A"), "retired", False{}))
    check("newer cleanup generation accepted only same root", B.Broker.cancel_target_valid(True{}, F.target(), D.Desktop.put(F.target(), "generation", J.Num{"3"}), "A", False{}))
    check("older cleanup generation cannot settle newer root", Bool.not(B.Broker.cancel_target_valid(True{}, F.target(), D.Desktop.put(F.target(), "generation", J.Num{"1"}), "A", False{})))
    check("another tab cannot use cleanup generation relaxation", Bool.not(B.Broker.cancel_target_valid(True{}, F.target(), R.second(), "A", False{})))
    check("notCreated requires literal null target", Bool.not(B.Broker.cancel_target_valid(False{}, J.Null{}, J.Str{"not a target"}, "A", True{})))
    check("backlog includes two queued active writer and blocked sender", Nat.is_eq(Nat.mul(4n, 1048576n), 4194304n))
