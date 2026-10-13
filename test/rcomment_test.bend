import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/board.bend as B
import ../src/core/hist.bend as H
import ../src/core/layers.bend as LY
import ../src/core/client.bend as U
import ../src/core/json.bend as J
import ../src/core/review.bend as RV
import ../src/core/mcp.bend as MC

# Design review comments end to end in the client and the hub's pure parts
# (core/review.bend, client.bend's Rc, hub.bend's review.comment, the agent's
# text and its tools).

def item(+k: String, +sig: U32, +layer: U32) -> B.Item:
  B.Item{k, sig, layer, B.PSeg{B.Pt{0.0, 0.0}, B.Pt{1.0, 1.0}, 0.2}, k}

def Show.items(xs: List<&2, B.Item>) -> String:
  match xs:
    case Nil{}:
      ""
    case B.Item{+k, _, +l, _, _} <> t:
      k ++ "@" ++ U32.show(l) ++ " " ++ Show.items(t)

def olds() -> List<&2, B.Item>:
  [item("a", 1, 12), item("b", 1, 5), item("c", 1, 12)]

def news() -> List<&2, B.Item>:
  [item("a", 2, 12), item("b", 2, 5), item("d", 1, 5)]

def labels(rs: List<&2, H.Ref>) -> List<&2, String>:
  match rs:
    case Nil{}:
      Nil{}
    case +r <> t:
      U.Hs.ref.label(r) <> labels(t)

def recv(+u: U.Ui, +text: String) -> U.Ui:
  U.Ui.recv(u, Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{}))

def ui(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}:
      u

def act(u: U.Ui, +a: String, +v: String) -> U.Ui:
  ui(U.Ui.act(u, a, v))

def sends(a: U.Act) -> String:
  match a:
    case U.Act{_, cs}:
      Nat.show(List.length(&2, U.Cmd, cs))

def state() -> M.State:
  M.State.replay([M.ProjectCreated{"p", "P", "/r", 1n}, M.ThreadCreated{"t", "p", "T", M.Local{}, "", "", "claude", "", 1n}], M.State.empty())

# thread t selected, its viewer on the board /r/b.kicad_pcb
def base() -> U.Ui:
  U.Ui.view_put(act(U.Ui.adopt(U.Ui.init(0n), state()), "select", "t"), "board", "/r/b.kicad_pcb")

def path(+u: U.Ui) -> String:
  U.Ui.view_get(u, "view.path")

def git(+c: String) -> String:
  H.Hist.git("/r/.git", c, "/r", "b.kicad_pcb")

def Show.sent(cs: List<&2, U.Cmd>) -> String:
  match cs:
    case Nil{}:
      ""
    case U.Send{+x} <> t:
      x ++ Show.sent(t)
    case _ <> t:
      Show.sent(t)

def sent(a: U.Act) -> String:
  match a:
    case U.Act{_, cs}:
      Show.sent(cs)

def add(+id: String, +file: String, +text: String, +at: Nat) -> M.Change:
  RV.Review.act("t", id, J.Json.obj([J.KV{"op", J.Str{"add"}}, J.KV{"file", J.Str{file}}, J.KV{"kind", J.Str{"board"}}, J.KV{"layer", J.Str{"F.Cu"}},
    J.KV{"x", J.Num{"12.5"}}, J.KV{"y", J.Num{"30"}}, J.KV{"item", J.Str{"fp:R1"}}, J.KV{"text", J.Str{text}}]), "person", at)

def reply(+id: String, +parent: String, +text: String, +at: Nat) -> M.Change:
  RV.Review.act("t", id, J.Json.obj([J.KV{"op", J.Str{"add"}}, J.KV{"parent", J.Str{parent}}, J.KV{"file", J.Str{"b.kicad_pcb"}}, J.KV{"text", J.Str{text}}]), "claude", at)

def op(+o: String, +id: String, +at: Nat) -> M.Change:
  RV.Review.act("t", "o" ++ Nat.show(at), J.Json.obj([J.KV{"op", J.Str{o}}, J.KV{"id", J.Str{id}}]), "person", at)

def st2(cs: List<&2, M.Change>) -> M.State:
  M.State.replay(List.append(&2, M.Change, [M.ProjectCreated{"p", "P", "/r", 1n}, M.ThreadCreated{"t", "p", "T", M.Local{}, "", "", "claude", "", 1n}], cs), M.State.empty())

def with(+cs: List<&2, M.Change>) -> U.Ui:
  U.Ui.view_put(act(U.Ui.adopt(U.Ui.init(0n), st2(cs)), "select", "t"), "board", "/r/b.kicad_pcb")

def npins(+u: U.Ui) -> String:
  Nat.show(List.length(&2, RV.Pin, U.Rc.pins(u)))

def opened(m: Maybe<&2, U.RcOpen>) -> String:
  match m:
    case Some{U.RcOpen{+id, +tx, +by, _, +res, +rs}}:
      id ++ "|" ++ tx ++ "|" ++ by ++ "|" ++ Bool.show(res) ++ "|" ++ Nat.show(List.length(&2, String, rs))
    case None{}:
      "none"

def res.body(r: MC.Res) -> String:
  match r:
    case MC.Res{+ok, +b, _}:
      Bool.show(ok) ++ " " ++ J.Json.show(b)

# the hub's history.refs answer naming the project's board
def refsr() -> String:
  "{\"t\":\"reply\",\"id\":1,\"ok\":true,\"result\":{\"thread\":\"t\",\"git\":\"/r/.git\",\"top\":\"/r\",\"refs\":\"\",\"pcb\":\"/r/b.kicad_pcb\",\"sch\":\"/r/b.kicad_sch\"}}"

def main() -> IO(Unit):
  +one = with([add("c1", "b.kicad_pcb", "Move R1 off the keepout", 2n)])
  +two = with([add("c1", "b.kicad_pcb", "Move R1 off the keepout", 2n), reply("c2", "c1", "Done, moved 2 mm", 3n), add("c3", "other.kicad_pcb", "elsewhere", 4n)])
  +done = with([add("c1", "b.kicad_pcb", "Move R1 off the keepout", 2n), op("resolve", "c1", 5n)])
  +noted = U.Ui.scratch_set(act(one, "rv-note", "40\t50\tB.Cu\tfp:C3"), "@f.rcnote", "Check C3 polarity")
  do IO<Unit>:
    C.Check.str("a comment pins on its file", npins(one), "1")
    C.Check.str("a reply and another file's do not", npins(two), "1")
    C.Check.str("a resolved one still pins", npins(done), "1")
    C.Check.str("the file is named from the thread's folder", U.Rc.rel(one), "b.kicad_pcb")
    C.Check.str("open counts", Nat.show(U.Rc.count(two)) ++ "|" ++ Nat.show(U.Rc.count(done)), "2|0")
    C.Check.str("rv-pin opens it with its replies", opened(U.Rc.open(act(two, "rv-pin", "c1"))), "c1|Move R1 off the keepout|person|False|1")
    C.Check.str("nothing open at first", opened(U.Rc.open(two)), "none")
    C.Check.str("rv-note keeps the place", U.Rc.at(act(one, "rv-note", "40\t50\tB.Cu\tfp:C3")), "40\t50\tB.Cu\tfp:C3")
    C.Check.str("sending it asks the hub", Bool.show(String.contains(sent(U.Ui.act(noted, "rv-note-send", "")), "review.comment")), "True")
    C.Check.str("with the place and the text", Bool.show(Bool.and(String.contains(sent(U.Ui.act(noted, "rv-note-send", "")), "Check C3 polarity"), String.contains(sent(U.Ui.act(noted, "rv-note-send", "")), "B.Cu"))), "True")
    C.Check.str("and forgets the place", U.Rc.at(act(noted, "rv-note-send", "")), "")
    C.Check.str("an empty note sends nothing", sent(U.Ui.act(act(one, "rv-note", "1\t2\t\t"), "rv-note-send", "")), "")
    C.Check.str("resolve asks the hub", Bool.show(String.contains(sent(U.Ui.act(one, "rv-resolve", "c1")), "\"resolve\"")), "True")
    C.Check.str("the Comments page", U.RpView.title(U.Rp.view(act(two, "rv-page", "comments"))), "Comments · 2 open")
    C.Check.str("lists them", Bool.show(String.contains(U.RpView.md(U.Rp.view(act(two, "rv-page", "comments"))), "Move R1 off the keepout")), "True")
    C.Check.str("an empty page says how", Bool.show(String.starts_with(U.RpView.note(U.Rp.view(act(base(), "rv-page", "comments"))), "No comments yet")), "True")
    C.Check.str("the agent reads the open ones", Bool.show(String.contains(RV.Review.agent(st2([add("c1", "b.kicad_pcb", "Move R1", 2n)]), "t", "hi"), "<review_comments>")), "True")
    C.Check.str("and nothing when none is open", RV.Review.agent(st2([add("c1", "b.kicad_pcb", "Move R1", 2n), op("resolve", "c1", 5n)]), "t", "hi"), "hi")
    C.Check.str("an add needs its text", Bool.show(RV.Review.op.ok("add", J.Json.obj([J.KV{"text", J.Str{"  "}}]))), "False")
    C.Check.str("a resolve needs its id", Bool.show(RV.Review.op.ok("resolve", J.Json.obj(Nil{}))) ++ Bool.show(RV.Review.op.ok("resolve", J.Json.obj([J.KV{"id", J.Str{"c1"}}]))), "FalseTrue")
    C.Check.str("an unknown op is refused", Bool.show(RV.Review.op.ok("burn", J.Json.obj([J.KV{"id", J.Str{"c1"}}]))), "False")
    C.Check.str("the agent's tool lists them", String.take(res.body(MC.Mcp.review.list(RV.Review.of_state(st2([add("c1", "b.kicad_pcb", "Move R1", 2n)]), "t"))), 28n), "True {\"open\":1,\"resolved\":0,")
    C.Check.str("a note kept with no file shows on the project's own board", Nat.show(List.length(&2, RV.Pin, U.Rc.pins(U.Ui.view_put(with([add("c9", "", "early note", 2n)]), "board", "")))), "1")
    C.Check.str("and once the hub named the file", Nat.show(List.length(&2, RV.Pin, U.Rc.pins(recv(U.Ui.view_put(with([add("c9", "", "early note", 2n)]), "board", ""), refsr())))), "1")
    C.Check.str("the board's own file is kept from the hub's answer", U.Rc.rel(recv(U.Ui.view_put(with([add("c1", "b.kicad_pcb", "x", 2n)]), "board", ""), refsr())), "b.kicad_pcb")
    C.Check.str("and its pins show on the board opened by default", npins(recv(U.Ui.view_put(with([add("c1", "b.kicad_pcb", "x", 2n)]), "board", ""), refsr())), "1")
    C.Check.str("kept, it is not asked again", sent(U.Ui.act(recv(U.Ui.view_put(with([add("c1", "b.kicad_pcb", "x", 2n)]), "board", ""), refsr()), "rv-pin", "")), "")
    C.Check.str("not kept, opening the thread asks", Bool.show(String.contains(sent(U.Ui.act(U.Ui.adopt(U.Ui.init(0n), st2([add("c1", "b.kicad_pcb", "x", 2n)])), "select", "t")), "history.refs")), "True")
