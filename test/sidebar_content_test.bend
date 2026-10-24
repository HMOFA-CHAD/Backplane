import Base
import ./check.bend as C
import ./sidebar_wire_test.bend as F
import ./sidebar_content_proof.bend as P
import ../src/server/thin-sidebar-wire.bend as W
import ../src/server/thin-actor.bend as A
import ../src/server/thin-view.bend as V
import ../src/core/json.bend as J
import ../src/server/thin-content-eq.bend as E

def request(exact: Bool, ack: String, rev: String) -> J.Json:
  J.Json.obj([J.KV{"hub", J.Str{"home"}}, J.KV{"generation", J.Str{"7"}}, J.KV{"epoch", J.Str{"epoch"}},
    J.KV{"target", V.Target.json("thread", "self")}, J.KV{"requestRevision", J.Num{rev}},
    J.KV{"sidebarRegion", J.Json.obj([J.KV{"version", J.Num{"1"}}, J.KV{"token", J.Str{ack}}, J.KV{"exactContent", J.Flag{exact}}])}])
def actor(r: W.Output) -> A.Actor:
  match r:
    case W.Output{a <> _, _}: a
    case _: F.actor("none")
def token(r: W.Output, field: String) -> String:
  J.Json.get_str(J.Json.get_obj(F.output(r), "sidebarRegion"), field, "full")
def initial() -> A.Actor:
  actor(W.Region.output(True{}, [F.actor("seq-1")], F.picture(), request(True{}, "", "1")))
def next(+a: A.Actor, p: J.Json, picture: J.Json) -> W.Output:
  W.Region.output(True{}, [A.Sidebar.save(True{}, a, "seq-2", F.sidebar())], picture, p)
def hit() -> W.Output:
  next(initial(), request(True{}, "1", "2"), F.picture())
def changed() -> J.Json:
  V.Obj.put(F.picture(), "shown", F.node("div", "app", [F.node("aside", "sidebar", [F.node("button", "changed-row", Nil{})]), F.node("main", "main", Nil{})]))
def retained(+a: A.Actor) -> String:
  Nat.show(List.length(&2, A.Memo, A.SidebarSent.keep(A.Sidebar.memos(a))))
def bool(b: Bool) -> String:
  Bool.pick(String, b, "true", "false")

law wrong_scope:
  for old: J.Json
  for node: J.Json
  {W.Content.equal(False{}, old, node) == False{} : Bool}
def wrong_scope(old, node): {==}
law sent_no_picture_authority:
  for scope: String
  for token: String
  for node: J.Json
  for +rest: List<&2, A.Memo>
  {W.Region.key(A.SidebarSent{scope, token, node} <> rest) == W.Region.key(rest) : String}
def sent_no_picture_authority(scope, token, node, rest): {==}

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("new full-sequence key binds only after exact sent sidebar comparison", token(hit(), "base"), "1")
    C.Check.str("fresh full-sequence picture key is retained", W.Region.key(A.Sidebar.memos(actor(hit()))), "seq-2")
    C.Check.str("changed actual sidebar sends full", token(next(initial(), request(True{}, "1", "2"), changed()), "base"), "")
    C.Check.str("missing ack sends full", token(next(initial(), request(True{}, "", "2"), F.picture()), "base"), "")
    C.Check.str("wrong ack sends full", token(next(initial(), request(True{}, "9", "2"), F.picture()), "base"), "")
    C.Check.str("legacy opt-out sends full after sequence change", token(next(initial(), request(False{}, "1", "2"), F.picture()), "base"), "")
    C.Check.str("legacy opt-out discards sent value", retained(actor(next(initial(), request(False{}, "1", "2"), F.picture()))), "0")
    C.Check.str("fresh actor never inherits exact content authority", token(next(F.actor("seq-1"), request(True{}, "1", "2"), F.picture()), "base"), "")
    C.Check.str("changed hub cannot reuse", token(next(initial(), V.Obj.put(request(True{}, "1", "2"), "hub", J.Str{"other"}), F.picture()), "base"), "")
    C.Check.str("changed generation cannot reuse", token(next(initial(), V.Obj.put(request(True{}, "1", "2"), "generation", J.Str{"8"}), F.picture()), "base"), "")
    C.Check.str("changed epoch cannot reuse", token(next(initial(), V.Obj.put(request(True{}, "1", "2"), "epoch", J.Str{"other"}), F.picture()), "base"), "")
    C.Check.str("changed target cannot reuse", token(next(initial(), V.Obj.put(request(True{}, "1", "2"), "target", V.Target.json("thread", "other")), F.picture()), "base"), "")
    C.Check.str("action never takes exact-content shortcut", token(next(initial(), V.Obj.put(request(True{}, "1", "2"), "action", J.Str{"send"}), F.picture()), "base"), "")
    C.Check.str("commands never take exact-content shortcut", token(next(initial(), request(True{}, "1", "2"), V.Obj.put(F.picture(), "cmds", J.Json.arr([J.Str{"command"}]))), "base"), "")
    C.Check.str("next target never takes exact-content shortcut", token(next(initial(), request(True{}, "1", "2"), V.Obj.put(F.picture(), "nextTarget", V.Target.json("thread", "other"))), "base"), "")
    C.Check.str("sent retention bounded to one value", retained(actor(next(actor(hit()), request(True{}, "1", "3"), F.picture()))), "1")
    C.Check.str("ordinary render retention preserves sent value", retained(A.Actor.remember(initial(), A.Memo{"key", 10n, False{}, J.Null{}})), "1")
    C.Check.str("sidebar image alone never supplies sent authority", token(next(A.SidebarImage.save(True{}, F.seed(), "image", F.sidebar()), request(True{}, "1", "2"), F.picture()), "base"), "")
    C.Check.str("mobile reply remains unadorned", token(W.Region.output(False{}, [initial()], F.picture(), request(True{}, "1", "2")), "base"), "full")
    C.Check.str("valid exact chain keeps current session", J.Json.get_str(F.output(hit()), "session", ""), "fresh-session")
    C.Check.str("valid exact chain keeps current window", J.Json.get_str(F.output(hit()), "window", ""), "fresh-window")
    C.Check.str("exact node equality keeps duplicate fields", bool(E.ContentEq.same(J.Obj{J.Field{"id", J.Num{"1"}, J.Field{"id", J.Num{"2"}, J.End{}}}}, J.Obj{J.Field{"id", J.Num{"2"}, J.Field{"id", J.Num{"1"}, J.End{}}}})), "false")
    C.Check.str("raw numeric lexemes remain distinct", bool(E.ContentEq.same(J.Num{"1"}, J.Num{"01"})), "false")
    C.Check.str("different JSON constructors remain distinct", bool(E.ContentEq.same(J.Num{"1"}, J.Str{"1"})), "false")
