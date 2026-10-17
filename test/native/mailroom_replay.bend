import Base
import ./mailroom_snap.bend as SN
import ./memo_replay.bend as EQ
import ../mailroom_client_test.bend as MC
import ../mailroom_parity_test.bend as PT
import ../check.bend as C
import ../../src/core/client.bend as U
import ../../src/core/json.bend as J
import ../../src/core/model.bend as M
import ../../src/core/mailview.bend as MV
import ../../src/app/mm.bend as MM
import ../../src/app/mailroom.bend as MR
import ../../src/app/bots.bend as B
import ../../src/app/nui.bend as N
import ../../src/app/layout.bend as L
import ../../src/app/cats.bend as CA

# The oracle always starts with empty wraps and explicitly redraws the
# body. It never reads BotM.key/same/due or the retained output to decide
# what should be drawn. Complete ops AND hits are compared.
type Case is Data:
  Case{name: String, ui: U.Ui, w: U32, h: U32}

type Counts is Data:
  Counts{frames: Nat, hit: Nat, stale_body: Nat, stale_frame: Nat}

def fresh(+ty: L.Ty, +n: N.Nui, +ws: Map<&2, B.PW>) -> L.Out:
  B.Bv.mail.draw(ws, ty, L.Lay.shrink(n, L.Lay.term_h(n)))

def one(+label: String, +ty: L.Ty, +n: N.Nui, +ws: Map<&2, B.PW>, +cold: Map<&2, B.PW>, count: Counts) -> IO(Counts):
  match count:
    case Counts{f, hit, sb, sf}:
      do IO<Counts>:
        +body_ok : Bool = EQ.Eqh.out(B.Bv.mail.out(ws, ty, n), fresh(ty, n, cold))
        +frame_ok : Bool = EQ.Eqh.out(B.Bv.frame.w(ty, L.TL.memos.now(Nil{}), CA.Cats.none(), ws, n), B.Bv.frame.w(ty, L.TL.memos.now(Nil{}), CA.Cats.none(), cold, n))
        C.Check.str(label ++ " body", Bool.show(body_ok), "True")
        C.Check.str(label ++ " full frame", Bool.show(frame_ok), "True")
        return Counts{1n+f, Nat.add(hit, B.Bv.mail.hit(ws, n)), Nat.add(sb, Bool.pick(Nat, body_ok, 0n, 1n)), Nat.add(sf, Bool.pick(Nat, frame_ok, 0n, 1n))}

def replay(cs: List<&2, Case>, +ty0: L.Ty, ws: Map<&2, B.PW>, count: Counts) -> IO(Counts):
  match cs:
    case Nil{}: IO.pure(Counts, count)
    case Case{name, +u, w, h} <> t:
      do IO<Counts>:
        +ty : L.Ty = L.Ty.with_loc(ty0, U.Lang.loc(u))
        +n : N.Nui = N.Nui.init(u, w, h)
        +kept : Map<&2, B.PW> = B.Bv.wraps.ix(ty, n, ws, U.Side.ix(U.Ui.state(u)))
        +cold : Map<&2, B.PW> = B.Bv.wraps.ix(ty, n, B.Bv.wraps.none(), U.Side.ix(U.Ui.state(u)))
        next : Counts <- one(name, ty, n, kept, cold, count)
        replay(t, ty0, kept, next)

def c(name: String, u: U.Ui) -> Case:
  Case{name, u, 1400, 900}

def base() -> U.Ui:
  SN.seed(U.Ui.scratch_set(MC.ui(), "@btab", "mail"))

def read(+u: U.Ui) -> U.Ui:
  U.Ui.scratch_set(U.Mailv.put(U.Ui.scratch_set(u, "@mr.conv", "c"), U.Mailv.read.put(U.Mailv.data(u), MV.Mv.put_read(U.Mailv.cache(u), MC.read_result(), False{}), "c", Map.new(&2, String), Nil{})), "@mr.to", "bot:b1")

def cases() -> List<&2, Case>:
  +u = base()
  +opened = read(u)
  +origin = U.Ui.fold([M.MessageFrom{"t1", "m1", "thread:x", "thread", "", 200001n}], opened)
  +newmail = U.Ui.fold([M.MailPosted{"m2", "c", "bot:b1", "person", "thread", "", "act", "new", 3n, 200001n}], origin)
  [c("initial", u), c("unchanged", u), c("one second", U.Ui.tick(u, 200001n)),
   c("before relative age boundary", U.Ui.tick(u, 200039n)), c("relative age boundary", U.Ui.tick(u, 200040n)),
   c("wall minute", U.Ui.tick(u, 200040n)), c("clock backwards", U.Ui.tick(u, 199999n)),
   c("origin", U.Ui.info_set(u, "origin", "second")), c("same revisions next generation", U.Ui.info_set(u, "local.generation", "next")),
   c("filter bot", U.Mailv.chip(u, "b2")), c("filter project", U.Ui.scratch_set(u, "@mr.project", "Sensor")),
   c("run expanded", U.Ui.scratch_set(u, "@mr.run", "1")), c("today", U.Ui.scratch_set(u, "@mr.status", "today")),
   c("scroll list", U.Ui.info_set(u, "pane:mr", "2")), c("search typed", U.Ui.scratch_set(u, "@f.mrsearch", "Deploy")),
   c("open", opened), c("open unchanged", opened), c("reply typed", U.Ui.scratch_set(opened, "@f.mrreply", "hello")),
   c("body scroll", U.Ui.info_set(opened, "pane:mrbody", "1")), c("origin metadata", origin), c("incoming header", newmail),
   c("terminal height", U.Ui.flag_on(opened, "term")),
   Case{"narrow", opened, 760, 900}, Case{"resized", opened, 1200, 720},
   c("Japanese", U.Ui.scratch_set(opened, "@lang.tag", "ja")),
   c("light", U.Act.ui(U.Ui.act(opened, "setting", "ui.theme=light"))),
   c("unrelated draft", U.Ui.scratch_set(u, "other-thread", "background draft")), c("final unchanged", u)]

def report(c: Counts) -> IO(Unit):
  match c:
    case Counts{f, +hit, body, frame}:
      do IO<Unit>:
        C.Check.str("body memo is exercised", Bool.show(Nat.is_gt(hit, 0n)), "True")
        C.Check.str("zero stale bodies", Nat.show(body), "0")
        C.Check.str("zero stale full frames", Nat.show(frame), "0")
        IO.print("frames=" ++ Nat.show(f) ++ " body_hits=" ++ Nat.show(hit))

def main() -> IO(Unit):
  do IO<Unit>:
    ty : L.Ty <- L.Ty.load()
    c : Counts <- replay(cases(), ty, B.Bv.wraps.none(), Counts{0n, 0n, 0n, 0n})
    report(c)
