import Base
import ../src/server/desktop-broker.bend as B
import ../src/core/desktop-browser.bend as D
import ../src/core/json.bend as J

def check(name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.print("ok " ++ name)
    case False{}: IO.die(Unit, 1, "FAIL " ++ name)

def obj(s: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(s), J.Null{})

def has(m: Maybe<&2, J.Json>) -> Bool:
  match m:
    case Some{_}: True{}
    case None{}: False{}

def contains(xs: List<&2, J.Json>, +value: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case h <> t: Bool.or(String.eq(J.Json.as_str(Some{h}, ""), value), contains(t, value))

def base(+out: Chan(String)) -> B.Broker:
  B.Broker{42, "epoch-A", "lease-A", Some{out}, obj("{\"ready\":true,\"owners\":{\"A\":{\"known\":true,\"drive\":\"agent\",\"recording\":true,\"revision\":7,\"tabId\":\"tab-A\",\"createId\":\"\"}},\"targets\":{\"tab-A\":{\"owner\":\"A\",\"tabId\":\"tab-A\",\"generation\":2,\"webContentsId\":4,\"ready\":true}}}"), Nil{}, 1n}

def main() -> IO(Unit):
  do IO<Unit>:
    +out : Chan(String) <- Chan.new(String, 32)
    +reply : Chan(String) <- Chan.new(String, 8)
    +q : Chan(B.Message) <- Chan.new(B.Message, 8)
    +b : B.Broker = base(out)
    +list : J.Json = B.Broker.owner_payload(b, "A")
    check("consumed create renews only list permission", String.eq(J.Json.show(J.Json.get_obj(list, "operations")), "[\"list\"]"))
    check("list-only grant omits consumed createId", Bool.not(has(J.Json.get(list, "createId"))))
    +creating : B.Broker = B.Broker.set_owner(b, "A", D.Desktop.put(B.Broker.owner(b, "A"), "createId", J.Str{"new-create"}))
    check("pending create correlation retained in renewal", String.eq(J.Json.get_str(B.Broker.owner_payload(creating, "A"), "createId", ""), "new-create"))
    +target : J.Json = B.Broker.target_payload(b, "A")
    check("target permission payload has exact seven fields", Nat.is_eq(D.Target.fields(target), 7n))
    check("target permission omits ambient readiness", Bool.not(has(J.Json.get(target, "ready"))))
    check("target permission omits ambient owner role", Bool.not(has(J.Json.get(target, "known"))))
    check("main recorder initialization is explicitly granted", contains(J.Json.elems(J.Json.get_obj(target, "operations")), "initialize"))
    +unknown : B.Broker = B.Broker.latch_unknown(b, "A")
    check("unknown latches original owner", B.Broker.unknown_owner(unknown, "A"))
    check("unknown does not block another owner", Bool.not(B.Broker.unknown_owner(unknown, "B")))
    +changed : B.Broker = B.Broker.policy(unknown, "A", True{}, "person", False{})
    check("new canonical person grant cannot clear UNKNOWN", B.Broker.unknown_owner(changed, "A"))
    check("unknown retains no-drive barrier", String.eq(B.Broker.effective_drive(changed, "A"), "none"))
    +released : B.Broker <- B.Broker.release_if(True{}, changed, "A")
    check("ordinary completion cannot release UNKNOWN latch", B.Broker.unknown_owner(released, "A"))
    +empty : B.Broker = B.Broker.empty_latched(B.Broker.meta(unknown))
    +restored : B.Broker = B.Broker.policy(empty, "A", True{}, "agent", True{})
    check("new controller policy cannot reset unresolved owner", B.Broker.unknown_owner(restored, "A"))
    +refused : B.Broker <- B.Broker.call(unknown, q, "evaluate", obj("{\"page\":\"A\",\"__desktopActor\":\"agent\"}"), reply)
    answer : Maybe<&1, String> <- Chan.recv(String, reply)
    check("UNKNOWN rejects before scheduling another command", Bool.not(J.Json.get_bool(obj(Maybe.default(&1, String, answer, "")), "ok", True{})))
    check("UNKNOWN rejection creates no pending work", List.is_empty(&2, B.Pending, B.Broker.pending(refused)))
    check("opaque dispatched failure is UNKNOWN", B.Broker.result_unknown(obj("{\"reply\":{\"ok\":false,\"dispatched\":true}}")))
    check("missing dispatch evidence is UNKNOWN", B.Broker.result_unknown(obj("{\"reply\":{\"ok\":false}}")))
    check("explicit predispatch refusal is known", Bool.not(B.Broker.result_unknown(obj("{\"reply\":{\"ok\":false,\"dispatched\":false}}"))))
    +pending : List<&2, B.Pending> = [B.Pending{"request-A", "A", B.Broker.public_target(B.Broker.target(b, "A")), 7n, reply}]
    check("result owner derives from original request", String.eq(B.Broker.pending_original_owner(pending, "request-A"), "A"))
    +closed : B.Broker <- B.Broker.close(B.Broker.replace_pending(b, pending), "fixture controller loss")
    check("controller loss preserves outstanding owner UNKNOWN", B.Broker.unknown_owner(closed, "A"))
    Chan.close(String, reply)
    Chan.close(B.Message, q)
