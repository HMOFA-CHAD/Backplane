import Base
import ../src/server/desktop-broker.bend as B
import ../src/core/desktop-browser.bend as D
import ../src/core/json.bend as J
import ./desktop_broker_test.bend as F

def check(name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.print("ok " ++ name)
    case False{}: IO.die(Unit, 1, "FAIL " ++ name)

def second() -> J.Json:
  F.obj("{\"owner\":\"A\",\"tabId\":\"tab-B\",\"generation\":1}")

def base(+out: Chan(String)) -> B.Broker:
  +b = F.state(out)
  B.Broker.set_target(B.Broker.set_owner(b, "A", D.Desktop.put(D.Desktop.put(B.Broker.owner(b, "A"), "createId", J.Str{""}), "activeTabId", J.Str{"tab-A"})), D.Desktop.put(D.Desktop.put(second(), "webContentsId", J.Num{"5"}), "ready", J.Flag{True{}}))

def activate(rows: List<&2, J.Json>, +id: String) -> List<&2, J.Json>:
  match rows:
    case Nil{}: Nil{}
    case +h <> t: D.Desktop.put(h, "active", J.Flag{String.eq(J.Json.get_str(h, "tabId", ""), id)}) <> activate(t, id)

def inventory(+b: B.Broker, id: String) -> J.Json:
  J.Json.obj([J.KV{"owner", J.Str{"A"}}, J.KV{"grantRevision", J.Num{Nat.show(J.Json.get_nat(B.Broker.owner(b, "A"), "revision", 0n))}}, J.KV{"tabs", J.Json.arr(activate(B.Broker.registry(b, "A"), id))}])

def pending(+b: B.Broker, +id: String, +target: J.Json, op: String, args: J.Json, reply: Chan(String)) -> B.Broker:
  B.Broker.replace_pending(B.Broker.command_put(b, id, B.Broker.command_initial("A", target, 7n, op, args)), [B.Pending{id, "A", target, 7n, reply}])

def outcome(+target: J.Json, revision: Nat) -> J.Json:
  J.Json.obj([J.KV{"owner", J.Str{"A"}}, J.KV{"dispatchTarget", target}, J.KV{"target", target}, J.KV{"grantRevision", J.Num{"7"}}, J.KV{"resultRevision", J.Num{Nat.show(revision)}}, J.KV{"reply", F.obj("{\"ok\":true,\"result\":{}}")}])

def main() -> IO(Unit):
  do IO<Unit>:
    +out : Chan(String) <- Chan.new(String, 128)
    +reply : Chan(String) <- Chan.new(String, 16)
    +q : Chan(B.Message) <- Chan.new(B.Message, 16)
    +events : Chan(String) <- Chan.new(String, 16)
    +b : B.Broker = base(out)
    check("known inventory contains exactly two registered roots", Nat.is_eq(List.length(&2, J.Json, B.Broker.registry(b, "A")), 2n))
    check("actual complete owner inventory validates", B.Broker.registry_valid(b, inventory(b, "tab-A")))
    check("inventory cannot omit registered live root", Bool.not(B.Broker.registry_valid(b, D.Desktop.put(inventory(b, "tab-A"), "tabs", J.Json.arr(Nil{})))))
    check("inventory rejects nonarray even when empty", Bool.not(B.Broker.registry_valid(B.Broker.empty(), F.obj("{\"tabs\":{}}"))))
    check("inventory requires one actual active root", Bool.not(B.Broker.registry_valid(b, inventory(b, "none"))))
    check("stale inventory revision cannot become current", Bool.not(B.Broker.registry_valid(b, D.Desktop.put(inventory(b, "tab-A"), "grantRevision", J.Num{"6"}))))
    +row : J.Json = D.Desktop.put(D.Desktop.put(D.Desktop.put(F.target(), "url", J.Str{"https://example.invalid/"}), "title", J.Str{"actual title"}), "active", J.Flag{True{}})
    check("normal metadata row has exact public fields", B.Broker.registry_entry_valid(b, "A", row))
    check("private recorder metadata cannot enter public tab row", Bool.not(B.Broker.registry_entry_valid(b, "A", D.Desktop.put(row, "documentNonce", J.Str{"private"}))))
    check("foreign owner row refused", Bool.not(B.Broker.registry_entry_valid(b, "A", D.Desktop.put(row, "owner", J.Str{"B"}))))
    check("stale target generation refused", Bool.not(B.Broker.registry_entry_valid(b, "A", D.Desktop.put(row, "generation", J.Num{"1"}))))
    check("nonstring metadata refused", Bool.not(B.Broker.registry_entry_valid(b, "A", D.Desktop.put(row, "url", J.Num{"2"}))))
    check("duplicate tab IDs refused", Bool.not(B.Broker.registry_entries_valid([row, row], b, "A", Nil{})))
    +selectArgs : J.Json = F.obj("{\"page\":\"A\",\"selectId\":\"tab-B\"}")
    check("select resolves exact registered owner root", D.Target.eq(D.Target.decode(B.Broker.request_target(b, "tabs", selectArgs)), D.Target.decode(second())))
    check("foreign target selection refused before dispatch", Bool.not(B.Broker.request_target_valid(b, "tabs", D.Desktop.put(selectArgs, "page", J.Str{"B"}))))
    check("explicit stale target not silently refreshed", Bool.not(B.Broker.request_target_valid(b, "select", J.Json.obj([J.KV{"page", J.Str{"A"}}, J.KV{"target", D.Desktop.put(second(), "generation", J.Num{"0"})}]))))
    check("explicit new tabs request starts distinct preparation", B.Broker.new_op("tabs", F.obj("{\"new\":true}")))
    +loading : B.Broker = B.Broker.set_target(b, D.Desktop.put(B.Broker.target(b, "A"), "ready", J.Flag{False{}}))
    +refused : B.Broker <- B.Broker.call(loading, q, "navigate", F.obj("{\"page\":\"A\",\"url\":\"https://example.invalid/\"}"), reply)
    answer : Maybe<&1, String> <- Chan.recv(String, reply)
    check("existing loading guest is refused without auto replacement", Bool.not(J.Json.get_bool(F.obj(Maybe.default(&1, String, answer, "")), "dispatched", True{})))
    check("loading refusal creates no pending preparation", Bool.not(B.Broker.preparing(refused, "A")))
    +selecting : B.Broker = pending(b, "select-command", second(), "tabs", selectArgs, reply)
    +selectionPayload : J.Json = D.Desktop.put(D.Desktop.put(inventory(selecting, "tab-B"), "dispatchId", J.Str{"select-command"}), "dispatchRevision", J.Num{"7"})
    +selected : B.Broker <- B.Broker.registry_apply(B.Broker.registry_valid(selecting, selectionPayload), selecting, selectionPayload, "tabs-event")
    check("actual selection updates active target", String.eq(J.Json.get_str(B.Broker.target(selected, "A"), "tabId", ""), "tab-B"))
    check("selection invalidates old mutation revision", Nat.is_eq(J.Json.get_nat(B.Broker.owner(selected, "A"), "revision", 0n), 8n))
    check("selection preserves canonical capture revision", Nat.is_eq(B.Broker.capture_revision(selected, "A"), 7n))
    check("original exact select has correlated outcome", B.Broker.result_valid_request(selected, "select-command", "A", second(), 7n, outcome(second(), 8n)))
    +unrelated : B.Broker = pending(b, "read-command", F.target(), "snapshot", F.obj("{}"), reply)
    +changed : B.Broker <- B.Broker.registry_apply(B.Broker.registry_valid(unrelated, inventory(unrelated, "tab-B")), unrelated, inventory(unrelated, "tab-B"), "different-active")
    check("unrelated active change cannot complete old command", Bool.not(J.Json.get_bool(B.Broker.command(changed, "read-command"), "valid", True{})))
    +closing : B.Broker = pending(b, "close-command", F.target(), "close_page", F.obj("{}"), reply)
    +event : J.Json = D.Desktop.put(F.target(), "type", J.Str{"closed"})
    +closePayload : J.Json = J.Json.obj([J.KV{"owner", J.Str{"A"}}, J.KV{"event", event}, J.KV{"grantRevision", J.Num{"7"}}, J.KV{"dispatchId", J.Str{"close-command"}}, J.KV{"dispatchRevision", J.Num{"7"}}])
    check("actual exact pending close correlates", B.Broker.closed_correlated(closing, closePayload, event, B.Broker.command(closing, "close-command")))
    check("arbitrary event type cannot retire registered guest", Bool.not(B.Broker.closed_valid(closing, D.Desktop.put(event, "type", J.Str{"record"}))))
    +closed : B.Broker <- B.Broker.closed_event(closing, closePayload, "closed-event")
    check("expected close does not latch UNKNOWN", Bool.not(B.Broker.unknown_owner(closed, "A")))
    check("closed target retained as exact pending outcome", J.Json.get_bool(J.Json.get_obj(J.Json.get_obj(B.Broker.meta(closed), "targets"), "tab-A"), "retired", False{}))
    check("close independently advances capture revision", Nat.is_eq(B.Broker.capture_revision(closed, "A"), 8n))
    +fallbackPayload : J.Json = D.Desktop.put(D.Desktop.put(inventory(closed, "tab-B"), "dispatchId", J.Str{"close-command"}), "dispatchRevision", J.Num{"7"})
    +fallback : B.Broker <- B.Broker.registry_apply(B.Broker.registry_valid(closed, fallbackPayload), closed, fallbackPayload, "fallback-inventory")
    check("remaining guest becomes actually active", String.eq(J.Json.get_str(B.Broker.target(fallback, "A"), "tabId", ""), "tab-B"))
    check("close outcome is original retired target not replacement", B.Broker.result_valid_request(fallback, "close-command", "A", F.target(), 7n, outcome(F.target(), 9n)))
    check("replacement target cannot impersonate closed outcome", Bool.not(B.Broker.result_valid_request(fallback, "close-command", "A", F.target(), 7n, D.Desktop.put(outcome(F.target(), 9n), "target", second()))))
    +crash : J.Json = D.Desktop.put(D.Desktop.put(event, "type", J.Str{"crashed"}), "generation", J.Num{"3"})
    +crashed : B.Broker <- B.Broker.closed_event(unrelated, J.Json.obj([J.KV{"event", crash}]), "crash-event")
    check("unexpected actual crash latches outstanding owner", B.Broker.unknown_owner(crashed, "A"))
    check("foreign retirement cannot affect owner registry", Bool.not(B.Broker.closed_valid(b, D.Desktop.put(event, "owner", J.Str{"B"}))))
    Chan.close(String, out)
    Chan.close(String, reply)
    Chan.close(B.Message, q)
    Chan.close(String, events)
