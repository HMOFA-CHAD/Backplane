import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/review.bend as R

def pcb(+x: F32, +y: F32, +l: String, +item: String) -> R.Anchor:
  R.Anchor{"hw/main.kicad_pcb", "", "board", l, x, y, item}

def sch() -> R.Anchor:
  R.Anchor{"hw/power.kicad_sch", "abc123", "schematic", "", 50.0, 25.5, ""}

def ch(+th: String, +id: String, +kind: String, +summary: String, +at: Nat) -> M.Change:
  M.ActivityLogged{th, id, "review", kind, summary, at}

def changes() -> List<&2, M.Change>:
  [ch("t", "e1", "add", R.Review.op.add("c1", pcb(10.5, 20.25, "F.Cu", "pad:U1.3"), "Trace too thin", "person", ""), 1n),
   ch("t", "e2", "add", R.Review.op.add("c2", sch(), "Add a pull-up", "claude", ""), 2n),
   ch("t", "e3", "add", R.Review.op.add("c1r", pcb(0.0, 0.0, "", ""), "Widened to 0.4", "claude", "c1"), 3n),
   ch("t", "e4", "resolve", R.Review.op.resolve("c2", "person"), 4n),
   ch("t", "e5", "add", R.Review.op.add("c3", pcb(1.0, 2.0, "B.Cu", ""), "Silk overlaps", "person", ""), 5n),
   ch("t", "e6", "add", R.Review.op.add("c3r", pcb(0.0, 0.0, "", ""), "Will move", "claude", "c3"), 6n),
   ch("t", "e7", "edit", R.Review.op.edit("c1", "Trace too thin for 2A"), 7n),
   ch("t", "e8", "resolve", R.Review.op.resolve("nope", "person"), 8n),
   ch("t", "e9", "add", R.Review.op.add("c9", sch(), "orphan reply", "claude", "ghost"), 9n),
   ch("t", "e10", "add", R.Review.op.add("c1", sch(), "duplicate id", "claude", ""), 10n),
   M.ActivityLogged{"t", "e11", "review", "add", "{not json", 11n},
   M.ActivityLogged{"t", "e12", "tool", "add", R.Review.op.add("cx", sch(), "wrong tone", "claude", ""), 12n},
   ch("u", "e13", "add", R.Review.op.add("cu", sch(), "other thread", "claude", ""), 13n),
   ch("t", "e14", "drop", R.Review.op.drop("c3"), 14n)]

def state() -> M.State:
  M.State.replay(changes(), M.State.empty())

def cs() -> List<&2, R.Comment>:
  R.Review.of_state(state(), "t")

def Show.cs(xs: List<&2, R.Comment>) -> String:
  match xs:
    case Nil{}:
      ""
    case +c <> t:
      R.Rv.id(c) ++ ":" ++ R.Rv.text(c) ++ ":" ++ Bool.pick(String, R.Rv.resolved(c), "r", "o") ++ " " ++ Show.cs(t)

def Show.pins(xs: List<&2, R.Pin>) -> String:
  match xs:
    case Nil{}:
      ""
    case +p <> t:
      R.Review.pin.id(p) ++ "/" ++ Nat.show(R.Review.pin.count(p)) ++ "/" ++ Bool.pick(String, R.Review.pin.resolved(p), "r", "o") ++ " " ++ Show.pins(t)

def Show.op(m: Maybe<&2, R.Op>) -> String:
  match m:
    case None{}:
      "none"
    case Some{R.Add{+c}}:
      "add " ++ R.Rv.id(c) ++ " " ++ R.Rv.file(c) ++ " " ++ R.Rv.where(c) ++ " " ++ R.Rv.item(c) ++ " by " ++ R.Rv.by(c)
    case Some{R.Resolve{+i, +b}}:
      "resolve " ++ i ++ " " ++ b
    case Some{R.Reopen{+i, +b}}:
      "reopen " ++ i ++ " " ++ b
    case Some{R.Edit{+i, +t}}:
      "edit " ++ i ++ " " ++ t
    case Some{R.Drop{+i}}:
      "drop " ++ i

def act(+kind: String, +summary: String) -> M.Entry:
  M.Act{"x", "t", "review", kind, summary, 5n}

def main() -> IO(Unit):
  +reopened = R.Review.fold(R.Review.ops(List.reverse(&2, M.Entry, [act("add", R.Review.op.add("a", sch(), "t", "p", "")), act("resolve", R.Review.op.resolve("a", "p")), act("reopen", R.Review.op.reopen("a", "p"))]), Nil{}))
  do IO<Unit>:
    C.Check.str("reviews filed", Nat.show(List.length(&2, M.Entry, M.State.reviews(state(), "t"))), "12")
    C.Check.str("reviews of another thread", Nat.show(List.length(&2, M.Entry, M.State.reviews(state(), "u"))), "1")
    C.Check.str("reviews: newest first", Show.op(R.Review.of(Maybe.default(&2, M.Entry, List.head(&2, M.Entry, M.State.reviews(state(), "t")), M.Msg{"", "", M.User{}, "", 0n}))), "drop c3")
    C.Check.str("still in the thread's entries", Nat.show(List.length(&2, M.Entry, M.State.mine(state(), "t"))), "13")
    C.Check.str("fold", Show.cs(cs()), "c1:Trace too thin for 2A:o c2:Add a pull-up:r c1r:Widened to 0.4:o ")
    C.Check.str("fold of nothing", Show.cs(R.Review.fold(Nil{})), "")
    C.Check.str("resolve then reopen", Show.cs(R.Review.fold([R.Add{R.Comment{"a", sch(), "t", "p", 1n, "", False{}}}, R.Resolve{"a", "p"}, R.Reopen{"a", "p"}])), "a:t:o ")
    C.Check.str("add, resolve", Show.cs(R.Review.fold([R.Add{R.Comment{"a", sch(), "t", "p", 1n, "", False{}}}, R.Resolve{"a", "p"}])), "a:t:r ")
    C.Check.str("drop takes its replies", Nat.show(List.length(&2, R.Comment, cs())), "3")
    C.Check.str("open", Show.cs(R.Review.open(cs())), "c1:Trace too thin for 2A:o ")
    C.Check.str("resolved", Show.cs(R.Review.resolved(cs())), "c2:Add a pull-up:r ")
    C.Check.str("count open", Nat.show(R.Review.count.open(cs())), "1")
    C.Check.str("replies", Show.cs(R.Review.replies(cs(), "c1")), "c1r:Widened to 0.4:o ")
    C.Check.str("for file", Show.cs(R.Review.for_file(cs(), "hw/main.kicad_pcb")), "c1:Trace too thin for 2A:o ")
    C.Check.str("pins: replies count, no pin of their own", Show.pins(R.Review.pins(cs(), "hw/main.kicad_pcb", "")), "c1/1/o ")
    C.Check.str("pins: other layer", Show.pins(R.Review.pins(cs(), "hw/main.kicad_pcb", "B.Cu")), "")
    C.Check.str("pins: same layer", Show.pins(R.Review.pins(cs(), "hw/main.kicad_pcb", "F.Cu")), "c1/1/o ")
    C.Check.str("pins: a sheet", Show.pins(R.Review.pins(cs(), "hw/power.kicad_sch", "F.Cu")), "c2/0/r ")
    C.Check.str("pins: unknown file", Show.pins(R.Review.pins(cs(), "x.kicad_pcb", "")), "")
    C.Check.str("roundtrip add", Show.op(R.Review.op.of("add", R.Review.op.add("c1", pcb(10.5, 20.25, "F.Cu", "pad:U1.3"), "Trace \"thin\"", "person", ""), 1n)),
      "add c1 hw/main.kicad_pcb (10.5, 20.25 mm, F.Cu) pad:U1.3 by person")
    C.Check.str("roundtrip resolve", Show.op(R.Review.op.of("resolve", R.Review.op.resolve("c1", "claude"), 1n)), "resolve c1 claude")
    C.Check.str("roundtrip reopen", Show.op(R.Review.op.of("reopen", R.Review.op.reopen("c1", "claude"), 1n)), "reopen c1 claude")
    C.Check.str("roundtrip edit", Show.op(R.Review.op.of("edit", R.Review.op.edit("c1", "a\nb"), 1n)), "edit c1 a\nb")
    C.Check.str("roundtrip drop", Show.op(R.Review.op.of("drop", R.Review.op.drop("c1"), 1n)), "drop c1")
    C.Check.str("unknown kind", Show.op(R.Review.op.of("nope", "{}", 1n)), "none")
    C.Check.str("other tone", Show.op(R.Review.of(M.Act{"x", "t", "tool", "add", "{}", 1n})), "none")
    C.Check.str("a message", Show.op(R.Review.of(M.Msg{"x", "t", M.User{}, "hi", 1n})), "none")
    C.Check.str("tone", R.Review.tone(), "review")
    C.Check.str("new id", R.Review.new_id("t", 3n), "rv:t:3")
    C.Check.str("moved: item changed", Bool.pick(String, R.Review.moved(Maybe.default(&2, R.Comment, List.head(&2, R.Comment, cs()), R.Comment{"", sch(), "", "", 0n, "", False{}}), ["x", "pad:U1.3"]), "yes", "no"), "yes")
    C.Check.str("moved: not changed", Bool.pick(String, R.Review.moved(Maybe.default(&2, R.Comment, List.head(&2, R.Comment, cs()), R.Comment{"", sch(), "", "", 0n, "", False{}}), ["x"]), "yes", "no"), "no")
    C.Check.str("moved: no item", Bool.pick(String, R.Review.moved(R.Comment{"", sch(), "", "", 0n, "", False{}}, [""]), "yes", "no"), "no")
    C.Check.str("prompt", R.Review.prompt(cs()),
      "<review_comments>\nOpen comments on the design (id, file, place, text). Answer or fix them, then reply or resolve with review_comment.\n- c1 hw/main.kicad_pcb (10.5, 20.25 mm, F.Cu): Trace too thin for 2A _(person)_\n    reply: Widened to 0.4 _(claude)_\n</review_comments>")
    C.Check.str("prompt: none open", R.Review.prompt(R.Review.fold([R.Add{R.Comment{"a", sch(), "t", "p", 1n, "", True{}}}])), "")
    C.Check.str("prompt: empty", R.Review.prompt(Nil{}), "")
    C.Check.str("md", R.Review.md(cs()),
      "- **hw/main.kicad_pcb** (10.5, 20.25 mm, F.Cu) — Trace too thin for 2A _(person)_\n  - Widened to 0.4 _(claude)_\n\nResolved\n\n- **hw/power.kicad_sch** (50, 25.5 mm) — Add a pull-up _(claude)_\n")
    C.Check.str("md: empty", R.Review.md(Nil{}), "")
    C.Check.str("issue title", R.Review.issue.title(R.Review.issue(cs(), R.Comment{"c", sch(), "First line\nsecond", "p", 1n, "", False{}})), "First line")
    C.Check.str("issue body", R.Review.issue.body(R.Review.issue(Nil{}, R.Comment{"c", sch(), "First line", "p", 1n, "", False{}})), "First line\n\nhw/power.kicad_sch (50, 25.5 mm) @ abc123\n")
    C.Check.str("reopened", Show.cs(reopened), "a:t:o ")
