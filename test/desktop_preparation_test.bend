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

def read(+out: Chan(String)) -> IO(J.Json):
  do IO<J.Json>:
    m : Maybe<&1, String> <- Chan.recv(String, out)
    return obj(Maybe.default(&1, String, m, ""))

def drain(n: Nat, +out: Chan(String)) -> IO(Unit):
  match n:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+k:
      do IO<Unit>:
        m : Maybe<&1, String> <- Chan.recv(String, out)
        drain(k, out)

def base(out: Chan(String)) -> B.Broker:
  B.Broker{42, "epoch", "lease", Some{out}, obj("{\"ready\":true,\"owners\":{\"A\":{\"known\":true,\"drive\":\"agent\",\"recording\":true,\"revision\":7,\"createId\":\"\",\"tabId\":\"\"}}}"), Nil{}, 1n}

def args() -> J.Json:
  obj("{\"page\":\"A\",\"__desktopActor\":\"agent\",\"url\":\"https://example.invalid/original\"}")

def target() -> J.Json:
  obj("{\"owner\":\"A\",\"tabId\":\"actual-tab\",\"generation\":1}")

def offer(+b: B.Broker, +t: J.Json) -> J.Json:
  J.Json.obj([J.KV{"owner", J.Str{"A"}}, J.KV{"prepareId", J.Str{J.Json.get_str(B.Broker.preparation(b, "A"), "prepareId", "")}},
    J.KV{"createId", J.Str{J.Json.get_str(B.Broker.preparation(b, "A"), "createId", "")}}, J.KV{"target", t}, J.KV{"webContentsId", J.Num{"44"}},
    J.KV{"grantRevision", J.Num{Nat.show(J.Json.get_nat(B.Broker.owner(b, "A"), "revision", 0n))}}])

def main() -> IO(Unit):
  do IO<Unit>:
    +out : Chan(String) <- Chan.new(String, 128)
    +reply : Chan(String) <- Chan.new(String, 8)
    +q : Chan(B.Message) <- Chan.new(B.Message, 8)
    +events : Chan(String) <- Chan.new(String, 8)
    +b : B.Broker = base(out)
    +preparing : B.Broker <- B.Broker.call(b, q, "navigate", args(), reply)
    +revoked : J.Json <- read(out)
    +grant : J.Json <- read(out)
    +capture : J.Json <- read(out)
    +prepare : J.Json <- read(out)
    check("initial request sends preparation instead of null-target command", String.eq(J.Json.get_str(prepare, "op", ""), "browser.prepare"))
    check("creation changes owner permission revision", Nat.is_eq(J.Json.get_nat(B.Broker.owner(preparing, "A"), "revision", 0n), 8n))
    check("preparation carries no original destination", String.eq(J.Json.get_str(J.Json.get_obj(prepare, "payload"), "url", "absent"), "absent"))
    check("preparation carries no original action", String.eq(J.Json.get_str(J.Json.get_obj(prepare, "payload"), "op", "absent"), "absent"))
    check("preparation creation correlation differs from request id", Bool.not(String.eq(J.Json.get_str(prepare, "id", ""), J.Json.get_str(J.Json.get_obj(prepare, "payload"), "createId", ""))))
    check("original args retained only inside service preparation", String.eq(J.Json.show(J.Json.get_obj(B.Broker.preparation(preparing, "A"), "args")), J.Json.show(args())))
    check("pending preparation cannot become ordinary result owner", String.is_empty(B.Broker.pending_original_owner(B.Broker.pending(preparing), J.Json.get_str(prepare, "id", ""))))
    check("preparation disconnect is not a dispatched user operation", Bool.not(J.Json.get_bool(J.Json.get_obj(B.Broker.pending_latches(B.Broker.pending(preparing), B.Broker.meta(preparing)), "unknownOwners"), "A", False{})))
    +second : B.Broker <- B.Broker.call(preparing, q, "navigate", args(), reply)
    +refusal : J.Json <- read(reply)
    check("same owner cannot overwrite outstanding create", Bool.not(J.Json.get_bool(refusal, "ok", True{})))
    check("same-owner refusal preserves exact preparation", String.eq(J.Json.show(B.Broker.preparation(second, "A")), J.Json.show(B.Broker.preparation(preparing, "A"))))
    check("stale offer revision refused", Bool.not(B.Broker.offer_preparation_valid(preparing, "A", D.Desktop.put(offer(preparing, target()), "grantRevision", J.Num{"7"}))))
    +offered : B.Broker <- B.Broker.frame_op("target.offer", preparing, J.Json.obj([J.KV{"id", J.Str{"offer-event"}}, J.KV{"payload", offer(preparing, target())}]), "A", "version", events)
    drain(4n, out)
    +offeredAck : J.Json <- read(out)
    check("offer acknowledgement binds revision after consuming create", Nat.is_eq(J.Json.get_nat(J.Json.get_obj(offeredAck, "payload"), "grantRevision", 0n), 9n))
    check("consumed create removed from owner", String.is_empty(J.Json.get_str(B.Broker.owner(offered, "A"), "createId", "")))
    check("offered guest is not dispatch ready", Bool.not(J.Json.get_bool(B.Broker.target(offered, "A"), "ready", True{})))
    check("preparation target grant refuses ordinary CDP", String.eq(J.Json.show(J.Json.get_obj(B.Broker.target_payload(offered, "A"), "cdpMethods")), "[]"))
    +changed : B.Broker = B.Broker.policy(offered, "A", True{}, "person", True{})
    check("takeover invalidates preparation lineage", Bool.not(B.Broker.preparation_current(changed, "A")))
    +restored : B.Broker = B.Broker.policy(changed, "A", True{}, "agent", True{})
    check("restoring old policy labels cannot revive preparation", Bool.not(B.Broker.preparation_current(restored, "A")))
    +finalTarget : J.Json = D.Desktop.put(target(), "generation", J.Num{"2"})
    +generated : B.Broker <- B.Broker.event(offered, offer(offered, finalTarget), "generation-event")
    drain(5n, out)
    check("second blank generation gets new permission revision", Nat.is_eq(J.Json.get_nat(B.Broker.owner(generated, "A"), "revision", 0n), 10n))
    check("expected generation preserves exact preparation lineage", B.Broker.preparation_current(generated, "A"))
    +ready : J.Json = D.Desktop.put(D.Desktop.put(D.Desktop.put(offer(generated, finalTarget), "recorderReady", J.Flag{True{}}), "recorderSourceSha256", J.Str{"2e4b03765cc4ae6595e32048555ffe27e750994a85c18b89027064f3c0c15350"}), "document", obj("{\"documentNonce\":\"final-main\",\"frameTreeNodeId\":3,\"frameToken\":\"final-frame\",\"webContentsId\":44}"))
    check("earlier blank target proof cannot complete readiness", Bool.not(B.Broker.ready_valid(generated, D.Desktop.put(ready, "target", target()))))
    check("final exact own document validates", B.Broker.ready_valid(generated, ready))
    +readied : B.Broker <- B.Broker.frame_op("target.ready", generated, J.Json.obj([J.KV{"id", J.Str{"ready-event"}}, J.KV{"payload", ready}]), "A", "version", events)
    drain(4n, out)
    check("readiness alone retains original preparation", B.Broker.preparing(readied, "A"))
    check("readiness alone has no ordinary dispatch pending", String.is_empty(B.Broker.pending_original_owner(B.Broker.pending(readied), J.Json.get_str(prepare, "id", ""))))
    +preparedPayload : J.Json = D.Desktop.put(ready, "intentId", J.Str{J.Json.get_str(B.Broker.preparation(readied, "A"), "intentId", "")})
    check("explicit prepared requires exact current revision", Bool.not(B.Broker.prepared_valid(readied, D.Desktop.put(preparedPayload, "grantRevision", J.Num{"9"}))))
    +dispatched : B.Broker <- B.Broker.prepared(readied, preparedPayload, "prepared-event")
    drain(4n, out)
    +call : J.Json <- read(out)
    check("prepared transition emits a new explicit command", String.eq(J.Json.get_str(call, "op", ""), "browser.call"))
    check("new command id differs from preparation id", Bool.not(String.eq(J.Json.get_str(call, "id", ""), J.Json.get_str(prepare, "id", ""))))
    check("ordinary dispatch has fresh permission revision", Nat.is_eq(J.Json.get_nat(J.Json.get_obj(call, "payload"), "grantRevision", 0n), 11n))
    check("dispatch preserves original exact operation", String.eq(J.Json.get_str(J.Json.get_obj(call, "payload"), "op", ""), "navigate"))
    check("dispatch preserves original exact args", String.eq(J.Json.show(J.Json.get_obj(J.Json.get_obj(call, "payload"), "args")), J.Json.show(args())))
    IO.print("actual-dispatch-target " ++ J.Json.show(J.Json.get_obj(J.Json.get_obj(call, "payload"), "target")))
    IO.print("expected-final-target " ++ J.Json.show(finalTarget))
    check("dispatch target is final returned generation", Bool.and(D.Target.valid(J.Json.get_obj(J.Json.get_obj(call, "payload"), "target")), D.Target.eq(D.Target.decode(J.Json.get_obj(J.Json.get_obj(call, "payload"), "target")), D.Target.decode(finalTarget))))
    check("completed preparation cannot dispatch again", Bool.not(B.Broker.prepared_valid(dispatched, preparedPayload)))
    check("old preparation timer cannot match new dispatch", Bool.not(B.Broker.pending_id(B.Broker.pending(dispatched), J.Json.get_str(prepare, "id", ""))))
    check("new command is classified as an outstanding dispatch", String.eq(B.Broker.pending_original_owner(B.Broker.pending(dispatched), J.Json.get_str(call, "id", "")), "A"))
    check("first client sequence is exactly one", B.Broker.client_sequence_valid(b, obj("{\"clientSequence\":1}")))
    check("client sequence rejects gaps", Bool.not(B.Broker.client_sequence_valid(b, obj("{\"clientSequence\":2}"))))
    +sequenced : B.Broker = B.Broker.sequence_apply(b, obj("{\"clientSequence\":4096}"))
    check("long lived controller exceeds old 1024 frame ceiling", B.Broker.client_sequence_valid(sequenced, obj("{\"clientSequence\":4097}")))
    check("completed old frame sequence cannot replay", Bool.not(B.Broker.client_sequence_valid(sequenced, obj("{\"clientSequence\":4096}"))))
    check("string sequence cannot be coerced", Bool.not(B.Broker.client_sequence_valid(b, obj("{\"clientSequence\":\"1\"}"))))
    Chan.close(String, out)
    Chan.close(String, reply)
    Chan.close(B.Message, q)
    Chan.close(String, events)
