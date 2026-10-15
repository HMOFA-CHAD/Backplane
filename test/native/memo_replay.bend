import Base
import ../../src/core/client.bend as U
import ../../src/core/model.bend as M
import ../../src/app/nui.bend as N
import ../../src/app/win.bend as W
import ../../src/app/layout.bend as L
import ../../src/app/theme.bend as T
import ../../src/gfx/raster.bend as R
import ../../src/gfx/tiles.bend as TI
import ../../src/app/bots.bend as BV
import ../../src/app/cats.bend as CA
import ../../src/core/json.bend as J
import ../../src/core/utf8.bend as U8
import ../../src/server/argv.bend as AV
import ../../src/app/mm.bend as MM
def ui_sel(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}:
      u

# what one frame leaves: the window state (with its hit regions), the memo
# and the tiles
type Kept is Data:
  Kept{n: N.Nui, memo: L.TLMemo, frames: TI.Frames}

type Times is Data:
  Times{ev: Nat, memo: Nat, lay: Nat, tiles: Nat, worst: Nat, each: String}

def hits(o: L.Out) -> List<&2, N.Hit>:
  match o:
    case L.Out{_, hs}:
      hs

def ops(o: L.Out) -> List<&2, R.Op>:
  match o:
    case L.Out{os, _}:
      os

def with_hits(n: N.Nui, hs: List<&2, N.Hit>, +ms: Nat) -> N.Nui:
  match n:
    case N.Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, _, _, vw}:
      N.Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, hs, ms, vw}

def prepared(+n: N.Nui, +ms: Nat) -> N.Nui:
  N.Lbx.stamp(N.Blink.stamp(N.Hover.stamp(N.Nui.prepare(n), ms), ms), ms)

def read.k(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(List<&2, U32>):
  (f, res) = r
  do IO<List<&2, U32>>:
    File.close(f)
    bs : List<&2, U32> <- IO.pass(List<&2, U32>, res)
    return bs

def read(+path: String) -> IO(List<&2, U32>):
  do IO<List<&2, U32>>:
    f : File <- IO.try(File, File.open(path, "r"))
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 200000000)
    read.k(r)

def copy(xs: List<&1, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      x <> copy(t)

def arg(+xs: List<&2, String>, +i: Nat) -> String:
  Maybe.default(&2, String, List.head(&2, String, List.drop(&2, String, xs, i)), "")

# the made-up log, or the real one named on the command line

# The main area's memo checked on a real log: the log less its last K
# events gives the window's state, then each of the K comes as a hub
# message of its own. At each step the main area is laid out from scratch
# and, when the memo's key says nothing it shows changed, compared with the
# memo's: they must be the same, op for op and hit for hit.
#   scripts/build-app.sh test/native/memo_replay.bend build/memo_replay
#   build/memo_replay EVENTS THREAD [K]

def lines(r: U8.Lines & List<&2, String>) -> List<&2, String>:
  (_, ls) = r
  ls

def items(ls: List<&2, String>, acc: List<&2, J.Json>) -> List<&2, J.Json>:
  match ls:
    case Nil{}:
      List.reverse(&2, J.Json, acc)
    case l <> t:
      items(t, Maybe.default(&2, J.Json, J.Json.parse(l), J.Null{}) <> acc)

def real(xs: List<&2, J.Json>, +sel: String) -> U.Ui:
  ui_sel(U.Ui.act(U.Ui.recv(U.Ui.init(1790180000n), J.Json.obj([J.KV{"t", J.Str{"log"}}, J.KV{"version", J.Str{"0.1.0"}},
    J.KV{"items", J.Json.arr(xs)}])), "select", sel))

def Eqh.hits(xs: List<&2, N.Hit>, ys: List<&2, N.Hit>) -> Bool:
  match xs ys:
    case Nil{} Nil{}:
      True{}
    case N.Hit{a0, a1, a2, a3, a4, a5} <> at N.Hit{b0, b1, b2, b3, b4, b5} <> bt:
      Bool.and(Bool.and(Bool.and(U32.is_eq(a0, b0), U32.is_eq(a1, b1)), Bool.and(U32.is_eq(a2, b2), U32.is_eq(a3, b3))),
        Bool.and(Bool.and(String.eq(a4, b4), String.eq(a5, b5)), Eqh.hits(at, bt)))
    case _ _:
      False{}

def Eqh.out(a: L.Out, b: L.Out) -> Bool:
  match a b:
    case L.Out{ao, ah} L.Out{bo, bh}:
      Bool.and(TI.Eq.ops(ao, bo), Eqh.hits(ah, bh))

type Tally is Data:
  Tally{steps: Nat, hits: Nat, bad: Nat, off: Nat, why: String}

def Tally.add(t: Tally, +hit: Bool, +ok: Bool, off: Bool, +what: String) -> Tally:
  match t:
    case Tally{s, h, b, o, +w}:
      Tally{1n+s, Nat.add(h, Bool.pick(Nat, hit, 1n, 0n)), Nat.add(b, Bool.pick(Nat, Bool.and(hit, Bool.not(ok)), 1n, 0n)), Nat.add(o, Bool.pick(Nat, off, 1n, 0n)),
        Bool.pick(String, Bool.and(hit, Bool.not(ok)), w ++ "\n  " ++ what, w)}

def Tally.show(t: Tally) -> String:
  match t:
    case Tally{s, h, b, o, w}:
      "steps " ++ Nat.show(s) ++ ", memo hits " ++ Nat.show(h) ++ ", memo hits unlike a fresh layout " ++ Nat.show(b) ++ ", steps not memoized " ++ Nat.show(o) ++ w

def with_ui(n: N.Nui, u: U.Ui) -> N.Nui:
  match n:
    case N.Nui{_, w, h, mx, my, sd, sc, ca, fo, pa, hi, ms, vw}:
      N.Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, hi, ms, vw}

def msg(x: J.Json) -> J.Json:
  J.Json.obj([J.KV{"t", J.Str{"changes"}}, J.KV{"items", J.Json.arr([x])}])

# each event its own message: the state, the touches, the main area again
def steps(xs: List<&2, J.Json>, +ty: L.Ty, +n0: N.Nui, +memo0: L.TLMemo, +mm: List<&2, MM.MainM>, tc: MM.TouchK, t: Tally) -> Tally:
  match xs:
    case Nil{}:
      t
    case +x <> rest:
      +o = msg(x)
      +n = prepared(with_ui(n0, U.Ui.recv(N.Nui.ui(n0), o)), 0n)
      +tc2 = MM.TouchK.msg(o, tc)
      +memo = L.Lay.memo(ty, n, memo0)
      +fresh = MM.Mm.lay(ty, memo, n)
      +keep = MM.MainM.keep(MM.Mm.fresh(mm, fresh, n, tc2))
      steps(rest, ty, with_hits(n, hits(fresh), 0n), memo, keep, tc2,
        Tally.add(t, MM.Mm.hits(mm, n, tc2), Eqh.out(MM.MainM.out(mm), fresh), List.is_empty(&2, MM.MainM, keep), String.take(J.Json.show(x), 160n)))

def step_nui(s: N.Step) -> N.Nui:
  match s:
    case N.Step{n, _, _}:
      n

# Typing, with no hub message: the sidebar's memo checked the same way
type Side is Data:
  Side{steps: Nat, hits: Nat, bad: Nat}

def Side.add(t: Side, +hit: Bool, +ok: Bool) -> Side:
  match t:
    case Side{s, h, b}:
      Side{1n+s, Nat.add(h, Bool.pick(Nat, hit, 1n, 0n)), Nat.add(b, Bool.pick(Nat, Bool.and(hit, Bool.not(ok)), 1n, 0n))}

def Side.show(t: Side) -> String:
  match t:
    case Side{s, h, b}:
      "typing: steps " ++ Nat.show(s) ++ ", sidebar memo hits " ++ Nat.show(h) ++ ", unlike a fresh one " ++ Nat.show(b)

def side.fresh(+ty: L.Ty, +n: N.Nui) -> L.Out:
  BV.Bv.side.a(ty, CA.Cats.none(), BV.Bv.wraps(ty, n, BV.Bv.wraps.none()), n)

def side.ev(+c: U32, +i: Nat) -> W.WinEv:
  match i:
    case 0n:
      W.WMove{(400 + c : U32), 500, 0}
    case _:
      W.WKey{c, c, 0, True{}, 0}

def typing(cs: String, +ty: L.Ty, +n0: N.Nui, +tc: MM.TouchK, +ms: List<&2, MM.SideM>, t: Side) -> Side:
  match cs:
    case SNil{}:
      t
    case SCon{Chr{+c}, rest}:
      +n = prepared(step_nui(N.Nui.event(n0, side.ev(c, Nat.mod(U32.to_nat(c), 4n)))), 0n)
      +key = MM.Sm.key(n, tc)
      +fresh = side.fresh(ty, n)
      typing(rest, ty, n, tc, [MM.SideM{key, fresh}], Side.add(t, MM.SideM.same(key, ms), Eqh.out(MM.SideM.out(ms), fresh)))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- AV.Argv.args()
    +as : List<&2, String> = copy(args)
    +ty : L.Ty <- L.Ty.load()
    bs : List<&2, U32> <- read(arg(as, 0n))
    +xs : List<&2, J.Json> = items(lines(U8.Lines.feed(U8.Lines.new(), bs)), Nil{})
    +k : Nat = Maybe.default(&2, Nat, Nat.read(arg(as, 2n)), 300n)
    +cut : Nat = Nat.sub(List.length(&2, J.Json, xs), k)
    +u : U.Ui = real(List.take(&2, J.Json, xs, cut), arg(as, 1n))
    +n : N.Nui = prepared(N.Nui.init(u, 1400, 900), 0n)
    +memo : L.TLMemo = L.Lay.memo(ty, n, L.TL.memo.none())
    +t : Tally = steps(List.drop(&2, J.Json, xs, cut), ty, with_hits(n, hits(MM.Mm.lay(ty, memo, n)), 0n), memo, Nil{}, MM.TouchK.none(), Tally{0n, 0n, 0n, 0n, ""})
    IO.print(Tally.show(t))
    +n2 : N.Nui = prepared(N.Nui.init(u, 1400, 900), 0n)
    IO.print(Side.show(typing("typing into the composer, and the pointer moving about", ty, n2, MM.TouchK.none(), [MM.SideM{MM.Sm.key(n2, MM.TouchK.none()), side.fresh(ty, n2)}], Side{0n, 0n, 0n})))
