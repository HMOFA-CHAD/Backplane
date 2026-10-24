import Base
import ./check.bend as C
import ../src/server/thin-actor.bend as A
import ../src/server/thin-sidebar-wire.bend as W
import ../src/server/thin-view.bend as V
import ../src/core/client.bend as U
import ../src/core/json.bend as J

def node(tag: String, key: String, kids: List<&2, J.Json>) -> J.Json:
  J.Json.obj([J.KV{"type", J.Str{"element"}}, J.KV{"tag", J.Str{tag}}, J.KV{"key", J.Str{key}}, J.KV{"attrs", J.Json.arr(Nil{})}, J.KV{"kids", J.Json.arr(kids)}])
def sidebar() -> J.Json:
  node("aside", "sidebar", [node("button", "actual-row", Nil{})])
def picture() -> J.Json:
  J.Json.obj([J.KV{"shown", node("div", "app", [sidebar(), node("main", "main", Nil{})])}, J.KV{"remoteReady", J.Flag{True{}}}, J.KV{"cmds", J.Json.arr(Nil{})}, J.KV{"session", J.Str{"fresh-session"}}, J.KV{"window", J.Str{"fresh-window"}}])
def actor(key: String) -> A.Actor:
  A.Sidebar.save(True{}, A.Actor.make(U.Ui.init(10n), "view", V.Target.json("thread", "self")), key, sidebar())
def request(version: String, ack: String, rev: String) -> J.Json:
  J.Json.obj([J.KV{"requestRevision", J.Num{rev}}, J.KV{"sidebarRegion", J.Json.obj([J.KV{"version", J.Num{version}}, J.KV{"token", J.Str{ack}}])}])
def output(r: W.Output) -> J.Json:
  match r:
    case W.Output{_, result}: result

def seed() -> A.Actor:
  W.Region.save(actor("exact-private-key"), "exact-private-key", "1")
def base(web: Bool, a: A.Actor, p: J.Json) -> String:
  J.Json.get_str(J.Json.get_obj(output(W.Region.output(web, [a], picture(), p)), "sidebarRegion"), "base", "full")
def count(xs: List<&2, A.Memo>) -> String:
  Nat.show(List.length(&2, A.Memo, xs))
def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("matching issued acknowledgement reuses exact private region", base(True{}, seed(), request("1", "1", "2")), "1")
    C.Check.str("missing acknowledgement sends full sidebar", base(True{}, seed(), request("1", "", "2")), "")
    C.Check.str("wrong acknowledgement sends full sidebar", base(True{}, seed(), request("1", "9", "2")), "")
    C.Check.str("changed exact dependencies send full sidebar", base(True{}, W.Region.save(actor("changed-private-key"), "exact-private-key", "1"), request("1", "1", "2")), "")
    C.Check.str("fresh actor never inherits another connection's token", base(True{}, actor("exact-private-key"), request("1", "1", "2")), "")
    C.Check.str("mobile retains full compatibility", base(False{}, seed(), request("1", "1", "2")), "full")
    C.Check.str("future protocol never enables reference", base(True{}, seed(), request("2", "1", "2")), "full")
    C.Check.str("invalid request revision never enables reference", base(True{}, seed(), request("1", "1", "0")), "full")
    C.Check.str("old client has byte-identical unadorned reply", J.Json.show(output(W.Region.output(True{}, [seed()], picture(), J.Json.obj(Nil{})))), J.Json.show(picture()))
    C.Check.str("seed token is only the request revision", J.Json.get_str(J.Json.get_obj(output(W.Region.output(True{}, [actor("exact-private-key")], picture(), request("1", "", "17"))), "sidebarRegion"), "token", ""), "17")
    C.Check.str("sidebar and receipt stay bounded across repeated saves", count(A.Sidebar.keep(A.Sidebar.memos(W.Region.save(W.Region.save(seed(), "key", "2"), "key", "3")))), "2")
    C.Check.str("command list preserved", J.Json.show(J.Json.get_obj(output(W.Region.output(True{}, [seed()], picture(), request("1", "1", "2"))), "cmds")), "[]")
    C.Check.str("current window retained", J.Json.get_str(output(W.Region.output(True{}, [seed()], picture(), request("1", "1", "2"))), "window", ""), "fresh-window")
    C.Check.str("current session retained", J.Json.get_str(output(W.Region.output(True{}, [seed()], picture(), request("1", "1", "2"))), "session", ""), "fresh-session")
