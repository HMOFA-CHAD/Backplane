import Base
import ./check.bend as C
import ../src/core/client.bend as U
import ../src/core/model.bend as M
import ../src/app/nui.bend as N
import ../src/app/win.bend as W
import ../src/app/layout.bend as L
import ../src/app/theme.bend as T
import ../src/gfx/raster.bend as R
import ../src/gfx/tiles.bend as TI

# Scrolling the window: the sidebar moves a tile a notch and stops at the
# end of its list; the thread shows earlier entries as the wheel nears its
# top (no button) and drops them back at the bottom; the timeline's memo
# lines up with a page that slid or grew (TL.align.of). Layout runs with
# the bitmap face here.

def para(+i: Nat) -> String:
  "Message " ++ Nat.show(i) ++ ": short."

def msg(+k: Nat, +th: String, +at: Nat) -> M.Change:
  M.MessagePosted{th, th ++ "m" ++ Nat.show(k), Bool.pick(M.Role, Nat.is_eq(Nat.mod(k, 2n), 0n), M.User{}, M.Assistant{}), para(k), Nat.add(at, k)}

def msgs(+n: Nat, +th: String, +at: Nat) -> List<&2, M.Change>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      msg(k, th, at) <> msgs(k, th, at)

def short(+k: Nat, +at: Nat) -> List<&2, M.Change>:
  M.ThreadCreated{"t" ++ Nat.show(1n+k), "p1", "Thread " ++ Nat.show(k), M.Local{}, "", "", "claude", "", at} <> msgs(20n, "t" ++ Nat.show(1n+k), at)

def threads(+n: Nat, +at: Nat) -> List<&2, M.Change>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      List.append(&2, M.Change, short(k, at), threads(k, at))

def log(+at: Nat) -> List<&2, M.Change>:
  List.concat(&2, M.Change, [[M.ProjectCreated{"p1", "board", "/tmp/board", at}, M.ThreadCreated{"t0", "p1", "Power sequencing", M.Local{}, "", "", "claude", "", at}],
    msgs(200n, "t0", at), threads(30n, at)])

def ui_sel(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}:
      u

def hits(o: L.Out) -> List<&2, N.Hit>:
  match o:
    case L.Out{_, hs}:
      hs

def with_hits(n: N.Nui, hs: List<&2, N.Hit>, +ms: Nat) -> N.Nui:
  match n:
    case N.Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, _, _, vw}:
      N.Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, hs, ms, vw}

def prepared(+n: N.Nui, +ms: Nat) -> N.Nui:
  N.Lbx.stamp(N.Blink.stamp(N.Hover.stamp(N.Nui.prepare(n), ms), ms), ms)

def step_nui(s: N.Step) -> N.Nui:
  match s:
    case N.Step{n, _, _}:
      n

def again(+ty: L.Ty, +n0: N.Nui) -> N.Nui:
  +n = prepared(n0, 0n)
  with_hits(n, hits(L.Lay.frame(ty, L.Lay.memo(ty, n, L.TL.memo.none()), n)), 0n)

def ev(+n: N.Nui, e: W.WinEv) -> N.Nui:
  step_nui(N.Nui.event(n, e))

def entry(+k: Nat) -> M.Entry:
  M.Msg{"m" ++ Nat.show(k), "t0", M.User{}, "text " ++ Nat.show(k), k}

# entries a (included) to b (excluded)
def entries(n: Nat, +a: Nat) -> List<&2, M.Entry>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      entry(a) <> entries(k, 1n+a)

def align.show(c: L.TLAlign) -> String:
  match c:
    case L.TLSame{}:
      "same"
    case L.TLDrop{d}:
      "drop " ++ Nat.show(d)
    case L.TLPad{k}:
      "pad " ++ Nat.show(k)

def align(+ty: L.Ty, es: List<&2, M.Entry>, old: List<&2, M.Entry>) -> String:
  align.show(L.TL.align.of(es, L.TL.memo.make(ty, old, 600, "t0")))

# n notches of the wheel at x, laid out after each
def wheel(k: Nat, +ty: L.Ty, +x: U32, +dir: U32, +n: N.Nui) -> N.Nui:
  match k:
    case 0n:
      n
    case 1n+j:
      wheel(j, ty, x, dir, again(ty, ev(n, W.WWheel{x, 400, dir})))

def sd(n: N.Nui) -> U32:
  match n:
    case N.Nui{_, _, _, _, _, s, _, _, _, _, _, _, _}:
      s

def sc(n: N.Nui) -> U32:
  match n:
    case N.Nui{_, _, _, _, _, _, s, _, _, _, _, _, _}:
      s

def main() -> IO(Unit):
  do IO<Unit>:
    +ty : L.Ty <- L.Ty.load()
    C.Check.str("a page that slid drops its oldest item", align(ty, entries(60n, 1n), entries(60n, 0n)), "drop 1")
    C.Check.str("a page added in front makes only it", align(ty, entries(120n, 0n), entries(60n, 60n)), "pad 60")
    C.Check.str("the same page stays", align(ty, entries(60n, 0n), entries(60n, 0n)), "drop 0")
    C.Check.str("a page dropped in front", align(ty, entries(60n, 60n), entries(120n, 0n)), "drop 60")
    C.Check.str("nothing in common", align(ty, entries(5n, 0n), entries(5n, 100n)), "same")
    +u : U.Ui = ui_sel(U.Ui.act(U.Ui.fold(log(1790000000n), U.Ui.init(1790000100n)), "select", "t0"))
    +n : N.Nui = again(ty, N.Nui.init(u, 1400, 900))
    +s1 : N.Nui = wheel(1n, ty, 100, 1, n)
    +s9 : N.Nui = wheel(40n, ty, 100, 1, n)
    +s10 : N.Nui = wheel(1n, ty, 100, 1, s9)
    C.Check.str("a sidebar notch is a tile", U32.show(sd(s1)), U32.show(N.Nui.notch()))
    C.Check.str("the sidebar stops at its end", Bool.show(U32.is_lt(sd(s9), (40 * N.Nui.notch() : U32))), "True")
    C.Check.str("and stays there", U32.show(sd(s10)), U32.show(sd(s9)))
    C.Check.str("a page at first", Nat.show(U.Page.more(N.Nui.ui(n), "t0")), "0")
    +t1 : N.Nui = wheel(40n, ty, 800, 0, n)
    C.Check.str("the wheel near the top shows earlier entries", Bool.show(Nat.is_gt(U.Page.more(N.Nui.ui(t1), "t0"), 0n)), "True")
    +t2 : N.Nui = wheel(200n, ty, 800, 1, t1)
    C.Check.str("back at the bottom", U32.show(sc(t2)), "0")
    C.Check.str("they go again", Nat.show(U.Page.more(N.Nui.ui(t2), "t0")), "0")
