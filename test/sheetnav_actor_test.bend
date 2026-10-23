import Base
import ./check.bend as C
import ../src/core/json.bend as J
import ../src/core/model.bend as M
import ../src/core/client.bend as U
import ../src/core/presentation.bend as P
import ../src/server/thin-actor.bend as A
import ../src/server/thin-view.bend as V

# Connection-owned tree state must fold privately, retain action ownership,
# and start empty after reconnect even when a renderer supplies an old cache.
def obj(+text: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{})

def state() -> M.State:
  M.State.replay([M.ThreadCreated{"t", "", "Fixture", M.Local{}, "", "", "codex", "", 1n}], M.State.empty())

def target() -> J.Json:
  V.Target.json("thread", "t")

def actor() -> A.Actor:
  A.Actor{U.Ui.reselect("t", U.Ui.adopt(U.Ui.init(100n), state())), "view", target(), Map.set(&2, String, Map.new(&2, String), "9", "pending scope"),
    [obj("{\"type\":\"send\",\"text\":\"fixture command\"}")], False{}, Nil{}}

def message(+gen: String, +rows: String) -> J.Json:
  J.Json.obj([J.KV{"t", J.Str{"sheets"}}, J.KV{"root", J.Str{"/fixture"}}, J.KV{"gen", J.Str{gen}}, J.KV{"rows", J.Str{rows}}])

def received() -> A.Actor:
  A.Actor.message(actor(), True{}, "hub", message("4294967296008", "fixture rows"))

def pending(a: A.Actor) -> String:
  match a:
    case A.Actor{_, _, _, p, _, _, _}: A.Actor.pending_scope(p, "9")

def request() -> J.Json:
  J.Json.obj([J.KV{"target", target()}, J.KV{"cid", J.Str{"fixture-device"}}, J.KV{"session", obj("{\"info\":{\"sheetgen:/fixture\":\"4294967296999\",\"sheets:/fixture\":\"old renderer cache\"},\"drafts\":{},\"outbox\":{}}") }])

def fresh() -> A.Actor:
  A.Actor.refresh(Nil{}, True{}, state(), obj("{}"), obj("{}"), 100n, request(), "view")

def check(+name: String, +yes: Bool) -> IO(Unit):
  C.Check.str(name, Bool.pick(String, yes, "yes", "no"), "yes")

def main() -> IO(Unit):
  do IO<Unit>:
    check("tree metadata never crosses raw thin notification wire", Bool.not(A.Message.on_wire(message("1", "fixture"))))
    C.Check.str("tree metadata reaches its private actor", U.Ui.info(A.Actor.ui(received()), "sheets:/fixture"), "fixture rows")
    check("tree projection is invalidated", A.Actor.dirty(received()))
    C.Check.str("tree metadata never settles pending action", pending(received()), "pending scope")
    C.Check.str("tree metadata preserves queued commands once", Nat.show(List.length(&2, J.Json, A.Actor.queued(received()))), "1")
    check("tree cache and generation are absent from serialized presentation", Bool.not(String.contains(J.Json.show(P.Session.pack(A.Actor.ui(received()))), "sheetgen:")))
    C.Check.str("new connection refuses renderer's old generation", U.Ui.info(A.Actor.ui(fresh()), "sheetgen:/fixture"), "")
    C.Check.str("same-second new actor lower counter is accepted after reconnect", U.Ui.info(A.Actor.ui(A.Actor.message(fresh(), True{}, "hub", message("4294967296000", "new actor rows"))), "sheets:/fixture"), "new actor rows")
