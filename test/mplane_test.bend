import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/codec.bend as K
import ../src/core/json.bend as J
import ../src/core/client.bend as U
import ../src/mobile/hubs.bend as H

# The status plane on the phones: the uberbot's card and the plane in the
# screen, merged over paired hubs (laws hubs_plane_*).

def items(cs: List<&2, M.Change>) -> List<&2, J.Json>:
  match cs:
    case Nil{}:
      Nil{}
    case c <> t:
      K.Change.encode(c) <> items(t)

def log(cs: List<&2, M.Change>) -> J.Json:
  J.Json.obj([J.KV{"t", J.Json.str("log")}, J.KV{"items", J.Json.arr(items(cs))}])

def now() -> Nat:
  200000n

# box: threads in several states, a bot at work promoted to uberbot, a
# room with news, a routine
def box() -> List<&2, M.Change>:
  [M.ProjectCreated{"p1", "One", "/a", 1n},
    M.ThreadCreated{"t1", "p1", "A", M.Local{}, "", "", "claude", "", 199000n}, M.TurnChanged{"t1", M.Running{}, 199001n}, M.AskOpened{"a1", "t1", "approval", "Bash", "ls", "", 199002n},
    M.ThreadCreated{"t4", "p1", "D", M.Local{}, "", "", "claude", "", 199300n}, M.TurnChanged{"t4", M.Running{}, 199301n},
    M.ThreadCreated{"t6", "p1", "F", M.Local{}, "", "", "claude", "", 199500n}, M.TurnChanged{"t6", M.Completed{}, 199501n},
    M.ThreadCreated{"bt1", "", "Kit", M.Local{}, "", "", "claude", "", 100n}, M.BotSet{"b1", "Kit", "bt1", 7n, "", 100n}, M.TurnChanged{"bt1", M.Running{}, 199900n},
    M.RoomSet{"r1", "ops", "b1", 150n}, M.RoomPosted{"m1", "r1", "b1", "hello", 0n, 199800n},
    M.RoutineSet{"rt1", "b1", "Digest", "0 9 * * *", "sum up", True{}, 160n},
    M.UberSet{"b1", "u1-a", 170n}]

# lap: its own thread at work, one waiting on a question
def lap() -> List<&2, M.Change>:
  [M.ProjectCreated{"p9", "Lap", "/lap", 50n},
    M.ThreadCreated{"t9", "p9", "Nine", M.Local{}, "", "", "claude", "", 199700n}, M.TurnChanged{"t9", M.Running{}, 199701n},
    M.ThreadCreated{"t8", "p9", "Eight", M.Local{}, "", "", "claude", "", 199600n}, M.AskOpened{"a8", "t8", "input", "", "?", "", 199601n}]

# the uberbot's replica on another machine (mirrored here as p2~b2): the
# machine mB tied it to the uid, and an exchange came in over link p2
def replica() -> List<&2, M.Change>:
  List.append(&2, M.Change, box(), [M.UberOp{"u1-a", "mB", 1n, "0000000100.000000.mB", "{\"k\":\"bind\",\"machine\":\"mB\",\"bot\":\"b2\",\"thread\":\"t2\",\"name\":\"Kit\"}", 100n},
    M.SettingSet{"uber.link.u1-a.mB", "p2", 101n}, M.ThreadCreated{"p2~t2", "", "Kit", M.Local{}, "", "", "claude", "", 100n}, M.BotSet{"p2~b2", "Kit", "p2~t2", 7n, "", 100n}])

def one(+cs: List<&2, M.Change>) -> H.Hubs:
  H.Hubs.after(H.Hubs.recv(H.Hubs.set(H.Hubs.init(now(), "c"), ["box:3787"]), "box:3787", log(cs)))

def two() -> H.Hubs:
  H.Hubs.after(H.Hubs.recv(
    H.Hubs.after(H.Hubs.recv(H.Hubs.set(H.Hubs.init(now(), "c"), ["lap:3787", "box:3787"]), "lap:3787", log(lap()))),
    "box:3787", log(box())))

def strs(js: List<&2, J.Json>, +key: String) -> String:
  match js:
    case Nil{}:
      ""
    case j <> t:
      J.Json.get_str(j, key, "") ++ ";" ++ strs(t, key)

def sec(+h: H.Hubs, +k: String, +field: String) -> String:
  strs(J.Json.elems(J.Json.get_obj(J.Json.get_obj(H.Hubs.screen(h), "plane"), k)), field)

def uber(+h: H.Hubs, +field: String) -> String:
  J.Json.get_str(J.Json.get_obj(H.Hubs.screen(h), "uber"), field, "")

def go(+h: H.Hubs, +a: String, +v: String) -> H.Hubs:
  H.Hubs.after(H.Hubs.act(h, a, v))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("no uberbot, no card", J.Json.show(J.Json.get_obj(H.Hubs.screen(one(lap())), "uber")), "null")
    C.Check.str("no uberbot, no plane", J.Json.show(J.Json.get_obj(H.Hubs.screen(one(lap())), "plane")), "null")
    C.Check.str("the card", uber(one(box()), "name"), "Kit")
    C.Check.str("its counts", uber(one(box()), "counts"), "1 need you · 2 running")
    C.Check.str("its cat", uber(one(box()), "cat"), "7:work")
    C.Check.str("needs you", sec(one(box()), "need", "id"), "box:3787|t1;")
    C.Check.str("a tap opens the thread", sec(one(box()), "need", "act"), "select;")
    C.Check.str("with the hub's value", sec(one(box()), "need", "value"), "box:3787|t1;")
    C.Check.str("running", sec(one(box()), "run", "id"), "box:3787|b1;box:3787|t4;")
    C.Check.str("no idle threads off the status tab", sec(one(box()), "idle", "id"), "")
    C.Check.str("idle on the status tab", sec(go(one(box()), "uber", "box:3787|b1"), "idle", "id"), "box:3787|t6;")
    C.Check.str("the room", sec(one(box()), "rooms", "id"), "box:3787|r1;")
    C.Check.str("the routine opens its bot's tab", sec(one(box()), "routines", "value"), "box:3787|b1|routines;")
    C.Check.str("one hub, no machine on a row", sec(one(box()), "need", "machine"), ";")
    C.Check.str("two hubs: waiting, most urgent first", sec(two(), "need", "id"), "box:3787|t1;lap:3787|t8;")
    C.Check.str("two hubs: running, newest first", sec(two(), "run", "id"), "box:3787|b1;lap:3787|t9;box:3787|t4;")
    C.Check.str("rows name their machine", sec(two(), "run", "machine"), "box;lap;box;")
    C.Check.str("bots at work", J.Json.show(J.Json.get_obj(J.Json.get_obj(H.Hubs.screen(two()), "plane"), "working")), "0")
    C.Check.str("counts over both", uber(two(), "counts"), "2 need you · 3 running")
    C.Check.str("a thread open: no plane", J.Json.show(J.Json.get_obj(H.Hubs.screen(go(one(box()), "select", "box:3787|t1")), "plane")), "null")
    C.Check.str("a thread open: the card stays", uber(go(one(box()), "select", "box:3787|t1"), "name"), "Kit")
    C.Check.str("a thread open: its counts wait for the plane", uber(go(one(box()), "select", "box:3787|t1"), "counts"), "")
    C.Check.str("back at the list: the plane", sec(go(go(one(box()), "select", "box:3787|t1"), "select", ""), "need", "id"), "box:3787|t1;")
    C.Check.str("the status tab: the plane", sec(go(one(box()), "uber", "box:3787|b1"), "need", "id"), "box:3787|t1;")
    C.Check.str("another tab of the uberbot: none", J.Json.show(J.Json.get_obj(H.Hubs.screen(go(go(one(box()), "uber", "box:3787|b1"), "bot-tab", "chat")), "plane")), "null")
    C.Check.str("the card's tap goes to its hub", H.Hubs.cur(go(go(two(), "select", "lap:3787|t9"), "uber", uber(two(), "id"))), "box:3787")
    C.Check.str("it shows the status tab", J.Json.get_str(J.Json.get_obj(H.Hubs.screen(go(two(), "uber", uber(two(), "id"))), "bot"), "tab", ""), "status")
    C.Check.str("without the replica a mirrored bot is listed", sec(one(List.append(&2, M.Change, box(), [M.ThreadCreated{"p3~t2", "", "Pip", M.Local{}, "", "", "claude", "", 100n}, M.BotSet{"p3~b2", "Pip", "p3~t2", 3n, "", 100n}])), "bots", "id"), "box:3787|p3~b2;")
    C.Check.str("the uberbot's replica elsewhere is not under Bots", sec(one(replica()), "bots", "id"), "")
    C.Check.str("nor on the Status tab", sec(go(one(replica()), "uber", "box:3787|b1"), "bots", "id"), "")
