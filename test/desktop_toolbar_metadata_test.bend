import Base
import ../src/server/desktop-broker.bend as B
import ../src/core/desktop-browser.bend as D
import ../src/core/json.bend as J
import ./desktop_broker_test.bend as F
import ./desktop_registry_close_test.bend as R
import ./desktop_preparation_test.bend as P
import ./desktop_creation_cancel_test.bend as C

def check(name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.print("ok " ++ name)
    case False{}: IO.die(Unit, 1, "FAIL " ++ name)

def rows() -> J.Json:
  F.obj("[{\"owner\":\"A\",\"tabId\":\"tab-A\",\"generation\":2,\"url\":\"https://example.invalid/一\",\"title\":\"ページ A\",\"active\":true},{\"owner\":\"A\",\"tabId\":\"tab-B\",\"generation\":1,\"url\":\"https://example.invalid/second\",\"title\":\"Second\",\"active\":false}]")

def inventory() -> J.Json:
  J.Json.obj([J.KV{"owner", J.Str{"A"}}, J.KV{"grantRevision", J.Num{"7"}}, J.KV{"tabs", rows()}])

def first(rows: List<&2, J.Json>) -> J.Json:
  match rows:
    case Nil{}: J.Null{}
    case h <> _: h

def second(rows: List<&2, J.Json>) -> J.Json:
  match rows:
    case Nil{}: J.Null{}
    case _ <> t: first(t)

def field_present(j: J.Json, key: String) -> Bool:
  Bool.not(Maybe.is_none(&2, J.Json, J.Json.get(j, key)))

def main() -> IO(Unit):
  do IO<Unit>:
    +out : Chan(String) <- Chan.new(String, 128)
    +ev : Chan(String) <- Chan.new(String, 16)
    +replay : Chan(String) <- Chan.new(String, 16)
    +reply : Chan(String) <- Chan.new(String, 8)
    +b : B.Broker = R.base(out)
    check("actual complete UI inventory validates", B.Broker.registry_valid(b, inventory()))
    +published : B.Broker <- B.Broker.frame_op("guest.tabs", b, J.Json.obj([J.KV{"id", J.Str{"tabs-event"}}, J.KV{"payload", inventory()}]), "A", "version", ev)
    +public : J.Json <- P.read(ev)
    +ack : J.Json <- P.read(out)
    check("normal metadata retains existing tabs event", String.eq(J.Json.get_str(public, "event", ""), "tabs"))
    check("normal metadata names exact owning page", String.eq(J.Json.get_str(public, "page", ""), "A"))
    check("address is actual selected page URL", String.eq(J.Json.get_str(public, "url", ""), "https://example.invalid/一"))
    check("public top-level schema has only four fields", Nat.is_eq(D.Target.fields(public), 4n))
    +tabs : List<&2, J.Json> = J.Json.elems(J.Json.get_obj(public, "tabs"))
    check("complete actual tab vector preserved", Nat.is_eq(List.length(&2, J.Json, tabs), 2n))
    check("first native root maps to existing UI id", String.eq(J.Json.get_str(first(tabs), "id", ""), "tab-A"))
    check("second native root order preserved", String.eq(J.Json.get_str(second(tabs), "id", ""), "tab-B"))
    check("Unicode title preserved exactly", String.eq(J.Json.get_str(first(tabs), "title", ""), "ページ A"))
    check("normal row has only five UI fields", Nat.is_eq(D.Target.fields(first(tabs)), 5n))
    check("toolbar retains actual selected flag", J.Json.get_bool(first(tabs), "active", False{}))
    check("metadata ACK remains private correlated response", String.eq(J.Json.get_str(ack, "id", ""), "tabs-event"))
    check("metadata publication changes no mutation grant", Nat.is_eq(J.Json.get_nat(B.Broker.owner(published, "A"), "revision", 0n), 7n))
    check("metadata publication changes no capture grant", Nat.is_eq(B.Broker.capture_revision(published, "A"), 7n))
    check("public row cannot leak document nonce", D.Desktop.bool_eq(field_present(first(tabs), "documentNonce"), False{}))
    check("public row cannot leak WC or grants", Bool.and(Bool.not(field_present(first(tabs), "webContentsId")), Bool.not(field_present(first(tabs), "grantRevision"))))
    +injected : J.Json = D.Desktop.put(D.Desktop.put(D.Desktop.put(first(J.Json.elems(rows())), "documentNonce", J.Str{"private-doc"}), "controllerLease", J.Str{"private-lease"}), "captureRevision", J.Num{"999"})
    +stripped : J.Json = B.Broker.public_row(injected, 0n)
    check("projection removes arbitrary extra private fields", Nat.is_eq(D.Target.fields(stripped), 5n))
    check("projection never publishes lease", Bool.not(field_present(stripped, "controllerLease")))
    check("projection never publishes capture revision", Bool.not(field_present(stripped, "captureRevision")))
    B.Broker.publish_cached(J.Json.get_obj(B.Broker.meta(published), "publicTabs"), replay)
    +cached : J.Json <- P.read(replay)
    check("new UI refresh gets exact cached normal metadata", String.eq(J.Json.show(cached), J.Json.show(public)))
    +q : Chan(B.Message) <- Chan.new(B.Message, 4)
    +result : Chan(B.Broker) <- Chan.new(B.Broker, 1)
    B.Broker.step(Some{B.Refresh{}}, published, q, "version", replay, next => F.finished(result, next))
    +refreshedEvent : J.Json <- P.read(replay)
    sameState : Maybe<&1, B.Broker> <- Chan.recv(B.Broker, result)
    check("actual Refresh message republishes cached normal event", String.eq(J.Json.show(refreshedEvent), J.Json.show(public)))
    check("actual Refresh creates no ordinary pending request", List.is_empty(&2, B.Pending, B.Broker.pending(F.state_result(sameState))))
    check("refresh creates no user operation pending", List.is_empty(&2, B.Pending, B.Broker.pending(published)))
    check("metadata event cannot confer readiness or target authority", Bool.not(field_present(public, "target")))
    +empty : J.Json = B.Broker.public_tabs(F.obj("{\"owner\":\"A\",\"tabs\":[]}"))
    check("actual empty inventory clears address", String.is_empty(J.Json.get_str(empty, "url", "not empty")))
    check("empty inventory keeps exact owning page", String.eq(J.Json.get_str(empty, "page", ""), "A"))
    +preparing : B.Broker <- B.Broker.prepare_start(P.base(out), "navigate", P.args(), reply)
    +cancelling : B.Broker <- B.Broker.prepare_failed(preparing, C.failed(preparing), "failed-event")
    +proof : J.Json = C.cancelled(cancelling, True{})
    check("invalid closeUnknown type cannot become false", Bool.not(B.Broker.cancel_receipt_valid(cancelling, D.Desktop.put(proof, "receipt", D.Desktop.put(J.Json.get_obj(proof, "receipt"), "closeUnknown", J.Str{"true"})))))
    check("actual sticky cleanup failure stays unresolved even if destroyed", Bool.not(B.Broker.cancel_destroyed(D.Desktop.put(proof, "receipt", D.Desktop.put(J.Json.get_obj(proof, "receipt"), "closeUnknown", J.Flag{True{}})))))
