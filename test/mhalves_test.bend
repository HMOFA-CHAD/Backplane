import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/codec.bend as K
import ../src/core/json.bend as J
import ../src/mobile/hubs.bend as H
import ../src/mobile/screen.bend as S
import ../src/mobile/app.bend as A

# The phones' bridge makes the screen in halves (hubs.bend's Hubs.lean):
# the list half from every client but its streamed text (Hubs.screen.fast,
# kept while its parts are the same), the open thread from the real ones
# (Hubs.opened), whose streamed reply it renders a paragraph at a time
# (bridge.js's liveNodes; here all at once, S.Mob.live.nodes). Put
# together they are the whole screen, field for field and in order. (The
# bench, test/tools/phone_lean_bench.ts --verify, checks it frame by frame
# on a real log; test/tools/phone_live_test.ts the reply's paragraphs.)

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

def box() -> List<&2, M.Change>:
  [M.ProjectCreated{"p1", "One", "/a", 1n},
    M.ThreadCreated{"t1", "p1", "A", M.Local{}, "", "", "claude", "", 199000n}, M.TurnChanged{"t1", M.Running{}, 199001n}, M.AskOpened{"a1", "t1", "approval", "Bash", "ls", "", 199002n},
    M.MessagePosted{"t1", "m1", M.User{}, "look at the board", 199003n},
    M.ThreadCreated{"t4", "p1", "D", M.Local{}, "", "", "claude", "", 199300n}, M.TurnChanged{"t4", M.Running{}, 199301n},
    M.ThreadCreated{"t6", "p1", "F", M.Local{}, "", "", "claude", "", 199500n}, M.TurnChanged{"t6", M.Completed{}, 199501n},
    M.ThreadCreated{"bt1", "", "Kit", M.Local{}, "", "", "claude", "", 100n}, M.BotSet{"b1", "Kit", "bt1", 7n, "", 100n}, M.TurnChanged{"bt1", M.Running{}, 199900n},
    M.RoomSet{"r1", "ops", "b1", 150n}, M.RoomPosted{"m1", "r1", "b1", "hello", 0n, 199800n},
    M.UberSet{"b1", "u1-a", 170n}]

def lap() -> List<&2, M.Change>:
  [M.ProjectCreated{"p9", "Lap", "/lap", 50n},
    M.ThreadCreated{"t9", "p9", "Nine", M.Local{}, "", "", "claude", "", 199700n}, M.TurnChanged{"t9", M.Running{}, 199701n},
    M.ThreadCreated{"t8", "p9", "Eight", M.Local{}, "", "", "claude", "", 199600n}, M.AskOpened{"a8", "t8", "input", "", "?", "", 199601n}]

def one() -> H.Hubs:
  H.Hubs.after(H.Hubs.recv(H.Hubs.set(H.Hubs.init(now(), "c"), ["box:3787"]), "box:3787", log(box())))

def two() -> H.Hubs:
  H.Hubs.after(H.Hubs.recv(
    H.Hubs.after(H.Hubs.recv(H.Hubs.set(H.Hubs.init(now(), "c"), ["lap:3787", "box:3787"]), "lap:3787", log(lap()))),
    "box:3787", log(box())))

def go(+h: H.Hubs, +a: String, +v: String) -> H.Hubs:
  H.Hubs.after(H.Hubs.act(h, a, v))

def delta(+h: H.Hubs, +key: String, +th: String, +text: String) -> H.Hubs:
  H.Hubs.after(H.Hubs.recv(h, key, J.Json.obj([J.KV{"t", J.Json.str("delta")}, J.KV{"thread", J.Json.str(th)}, J.KV{"text", J.Json.str(text)}])))

# the open thread with its streamed reply put in
def thread(+t: J.Json, +h: H.Hubs) -> J.Json:
  match t:
    case J.Obj{fs}:
      J.Obj{H.Hubs.pl.put(fs, "live", A.live_nodes(A.live_text(h)))}
    case x:
      x

# the screen from its halves, as the bridge puts it together
def halves.k(j: J.Json, +h: H.Hubs) -> String:
  match j:
    case J.Obj{fs}:
      J.Json.show(J.Obj{H.Hubs.pl.put(fs, "thread", thread(A.focus(h), h))})
    case x:
      J.Json.show(x)

def halves(+h: H.Hubs) -> String:
  halves.k(A.screen_list(A.lean(h)), h)

def whole(+h: H.Hubs) -> String:
  J.Json.show(A.screenj(h))

def same(+h: H.Hubs) -> String:
  Bool.pick(String, String.eq(halves(h), whole(h)), "same", "differ")

def reply() -> String:
  "Looked at it.\n\n- U3 is fine\n- the *3V3* rail droops\n\n```\nnet 3V3\n\nnet GND\n```\n\nSee http://x.y/z and src/a.kicad_pcb"

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("one hub, the list", same(one()), "same")
    C.Check.str("two hubs, the list", same(two()), "same")
    C.Check.str("a thread open", same(go(one(), "select", "box:3787|t1")), "same")
    C.Check.str("a thread open, a reply streaming", same(delta(go(one(), "select", "box:3787|t1"), "box:3787", "t1", reply())), "same")
    C.Check.str("another thread's reply streaming", same(delta(go(one(), "select", "box:3787|t1"), "box:3787", "t4", reply())), "same")
    C.Check.str("two hubs, a thread of the other hub open, streaming", same(delta(go(two(), "select", "lap:3787|t9"), "lap:3787", "t9", reply())), "same")
    C.Check.str("a bot open", same(go(one(), "bot", "box:3787|b1")), "same")
    C.Check.str("the open thread's reply is its text", A.live_text(delta(go(one(), "select", "box:3787|t1"), "box:3787", "t1", "abc")), "abc")
    C.Check.str("a list has no open thread", J.Json.show(A.focus(one())), "null")
    C.Check.str("the lean hubs make the same list", J.Json.show(J.Json.get_obj(A.screen_list(A.lean(delta(go(one(), "select", "box:3787|t1"), "box:3787", "t1", reply()))), "projects")),
      J.Json.show(J.Json.get_obj(A.screenj(delta(go(one(), "select", "box:3787|t1"), "box:3787", "t1", reply())), "projects")))
    C.Check.str("a reply rendered in two paragraphs is the one rendered whole",
      J.Json.show(J.Json.arr(List.append(&2, J.Json, J.Json.elems(S.Mob.live.nodes("one\n\n")), J.Json.elems(S.Mob.live.nodes("two *x*\n"))))),
      J.Json.show(S.Mob.live.nodes("one\n\ntwo *x*\n")))
