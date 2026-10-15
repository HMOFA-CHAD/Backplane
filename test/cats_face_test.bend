import Base
import ./check.bend as C
import ../src/app/cats.bend as CA
import ../src/app/bots.bend as BV
import ../src/gfx/raster.bend as R
import ../src/gfx/draw.bend as D
import ../src/core/utf8.bend as U

# The bots' cats face the way they did when the layout drew them
# (c76ebd46b): each cat, posed at a fixed clock and drawn the window's
# way (bots.bend's Spot.ops, and Fronted.of from an anchor), is pixel for
# pixel the golden frame test/fixtures/cats-face/golden.txt, which that
# commit rendered (Cats.draw's ops among the layout's, turned around by
# Lay.rev): 40 x 40 frames, a cat 28 px at (6, 6), a line a row.

def golden(ls: List<&2, String>, +name: String) -> String:
  match ls:
    case Nil{}:
      "(no golden " ++ name ++ ")"
    case +l <> t:
      Bool.pick(String, String.starts_with(l, name ++ " "), String.drop(l, Nat.add(String.length(name), 1n)), golden(t, name))

# row y's pixels, x from n - 1 down to 0 onto acc
def row(n: Nat, +img: Image, +d: Nat, +y: U32, acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+i0:
      +i = i0
      row(i, img, d, y, U32.show(R.Img.at(d, img, U32.from_nat(i), y)) ++ "," ++ acc)

# rows y < n that differ from the golden's, counted
def rows(n: Nat, +img: Image, +d: Nat, +g: List<&2, String>, +name: String, +acc: Nat) -> Nat:
  match n:
    case 0n:
      acc
    case 1n+i0:
      +i = i0
      rows(i, img, d, g, name, Bool.pick(Nat, String.eq(row(40n, img, d, U32.from_nat(i), ""), golden(g, name ++ "/" ++ Nat.show(i))), acc, 1n+acc))

def frame(ops: List<&2, R.Op>, +g: List<&2, String>, +name: String) -> String:
  +img = R.Frame.render(40, 40, ops, 1118481)
  Nat.show(rows(40n, img, R.Frame.depth(40, 40), g, name, 0n)) ++ " rows differ"

def spot(+look: Nat, +mood: String) -> BV.Spot:
  BV.Spot{look, mood, 28, 6, 6, D.Clip.all()}

def cat(+cache: Map<&2, CA.CatF>, +look: Nat, +mood: String, +ms: Nat, +g: List<&2, String>, +name: String) -> String:
  frame(BV.Spot.ops(spot(look, mood), cache, ms), g, name)

def fronted(f: BV.Fronted) -> List<&2, R.Op>:
  match f:
    case BV.Fronted{os, _, _}:
      os

# the same cat as a frame's anchor and hit, through Fronted.of
def front(+look: Nat, +mood: String, +ms: Nat, +g: List<&2, String>, +name: String) -> String:
  frame(fronted(BV.Fronted.of([BV.Spot.anchor(D.Clip.all(), 6, 6, 28)], [BV.Spot.hit(look, mood, D.Clip.all(), 6, 6, 28)], CA.Cats.none(), ms)), g, name)

def lines.r(r: U.Lines & List<&2, String>) -> List<&2, String>:
  (_, ls) = r
  ls

def file.done(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(List<&2, String>):
  (f, res) = r
  do IO<List<&2, String>>:
    File.close(f)
    return lines.r(U.Lines.feed(U.Lines.new(), Result.default(&1, &1, U32 & String, List<&2, U32>, res, Nil{})))

def file.sized(r: File & Result<&1, &1, U32 & String, U32>) -> IO(List<&2, String>):
  (f, res) = r
  IO.bind(File & Result<&1, &1, U32 & String, List<&2, U32>>, List<&2, String>, File.read_bytes(f, U32.max(Result.default(&1, &1, U32 & String, U32, res, 0), 1)), file.done)

def file.opened(r: Result<&1, &1, U32 & String, File>) -> IO(List<&2, String>):
  match r:
    case Done{f}:
      IO.bind(File & Result<&1, &1, U32 & String, U32>, List<&2, String>, File.size(f), file.sized)
    case Fail{_}:
      IO.pure(List<&2, String>, Nil{})

def file(path: String) -> IO(List<&2, String>):
  IO.bind(Result<&1, &1, U32 & String, File>, List<&2, String>, File.open(path, "r"), file.opened)

def main() -> IO(Unit):
  do IO<Unit>:
    +g : List<&2, String> <- file("test/fixtures/cats-face/golden.txt")
    C.Check.str("cat 0 idle faces as before", cat(CA.Cats.none(), 0n, "idle", 1000n, g, "0-idle"), "0 rows differ")
    C.Check.str("cat 1 idle faces as before", cat(CA.Cats.none(), 1n, "idle", 1000n, g, "1-idle"), "0 rows differ")
    C.Check.str("cat 2 at work faces as before", cat(CA.Cats.none(), 2n, "work", 1500n, g, "2-work"), "0 rows differ")
    C.Check.str("cat 3 waiting faces as before", cat(CA.Cats.none(), 3n, "wait", 2300n, g, "3-wait"), "0 rows differ")
    C.Check.str("a cached pose faces as before", cat(CA.Cats.warm(CA.Cats.none(), 1n, "work", 28, 1500n), 1n, "work", 1500n, g, "1-work-cached"), "0 rows differ")
    C.Check.str("a cat in front of the frame faces as before", front(2n, "work", 1500n, g, "2-work"), "0 rows differ")
