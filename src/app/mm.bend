import Base
import ../core/json.bend as J
import ../core/model.bend as M
import ../core/codec.bend as C
import ../core/client.bend as U
import ../core/vt.bend as VT
import ./nui.bend as N
import ./layout.bend as L

# The main area's memo. A frame lays the main area (the open thread, its
# Subagents panel, composer...) out again only when something it shows may
# have changed; otherwise it takes the last frame's. With agents streaming
# in other threads most frames changed nothing there.
#
# What may have changed is told by touches: each hub message counts one,
# and every change it folds marks the threads it touches (client.bend's
# Touch.of, which names every kind of change; anything not clearly one
# thread's touches all). Any other message (a log, another machine's
# state, the person's input) touches all. The key is the open thread's,
# its parent's and its children's last touches, the last touch of all, and
# every field of the window the main area reads (Mm.key). Equal keys, the
# same main area (test/native/memo_replay.bend checks it on a real log).

# n: messages counted; g: the last that touched all; r: the last that may
# have changed which threads are whose parent or child otherwise than by
# touching both (a setting, a state handed over: client.bend's Touch.of
# names it "!"); m: each thread's last
type TouchK is Data:
  TouchK{n: Nat, g: Nat, r: Nat, m: Map<&2, Nat>}

def TouchK.none() -> TouchK:
  TouchK{0n, 0n, 0n, Map.new(&2, Nat)}

def TouchK.of(ks: List<&2, TouchK>) -> TouchK:
  match ks:
    case Nil{}:
      TouchK.none()
    case k <> _:
      k

def TouchK.tick(t: TouchK) -> TouchK:
  match t:
    case TouchK{n, g, r, m}:
      TouchK{1n+n, g, r, m}

def TouchK.all(t: TouchK) -> TouchK:
  match t:
    case TouchK{+n, _, _, m}:
      TouchK{1n+n, 1n+n, 1n+n, m}

def TouchK.one.k(i: Nat, +id: String, t: TouchK) -> TouchK:
  match i t:
    case 0n TouchK{+n, _, r, m}:
      TouchK{n, n, r, m}
    case 1n TouchK{+n, g, _, m}:
      TouchK{n, g, n, m}
    case _ TouchK{+n, g, r, m}:
      TouchK{n, g, r, Map.set(&2, Nat, m, id, n)}

def TouchK.ids(ids: List<&2, String>, t: TouchK) -> TouchK:
  match ids:
    case Nil{}:
      t
    case +id <> rest:
      TouchK.ids(rest, TouchK.one.k(C.Codec.pos(["*", "!"], id), id, t))

# a change folded (one the client cannot read touches all)
def TouchK.change(m: Maybe<&2, M.Change>, t: TouchK) -> TouchK:
  match m:
    case Some{c}:
      TouchK.ids(U.Touch.of(c), t)
    case None{}:
      TouchK.ids(["*", "!"], t)

def TouchK.items(xs: List<&2, J.Json>, t: TouchK) -> TouchK:
  match xs:
    case Nil{}:
      t
    case x <> rest:
      TouchK.items(rest, TouchK.change(C.Change.decode(x), t))

def TouchK.msg.k(i: Nat, +o: J.Json, t: TouchK) -> TouchK:
  match i:
    case 0n:
      TouchK.items(J.Json.elems(J.Json.get_obj(o, "items")), TouchK.tick(t))
    case 1n:
      t
    case 2n:
      t
    case 3n:
      t
    case _:
      TouchK.all(t)

# a hub message: its changes touch what they touch; another thread's
# streamed text, its end (which the client does not read) and a heartbeat
# touch nothing (the open thread's own text
# is in the key); anything else touches all
def TouchK.msg(+o: J.Json, t: TouchK) -> TouchK:
  TouchK.msg.k(C.Codec.pos(["changes", "delta", "hb", "delta_end"], J.Json.get_str(o, "t", "")), o, t)

def TouchK.at.k(r: Map<&2, Nat> & Nat) -> Nat:
  (_, v) = r
  v

def TouchK.at(+t: TouchK, +id: String) -> Nat:
  match t:
    case TouchK{_, _, _, +m}:
      TouchK.at.k(Map.get(Nat, 0n, m, id))

def TouchK.m(t: TouchK) -> Map<&2, Nat>:
  match t:
    case TouchK{_, _, _, m}:
      m

def TouchK.g(+t: TouchK) -> Nat:
  match t:
    case TouchK{_, g, _, _}:
      g

def TouchK.r(+t: TouchK) -> Nat:
  match t:
    case TouchK{_, _, r, _}:
      r

# The key
# -------

def Mm.children(ts: List<&2, M.Task>) -> List<&2, String>:
  match ts:
    case Nil{}:
      Nil{}
    case M.Task{_, _, +c, _, _, _, _, _, _} <> t:
      c <> Mm.children(t)

def Mm.stamps(ids: List<&2, String>, +t: TouchK) -> String:
  match ids:
    case Nil{}:
      ""
    case +id <> rest:
      id ++ "=" ++ Nat.show(TouchK.at(t, id)) ++ "," ++ Mm.stamps(rest, t)

def Mm.strs(xs: List<&2, Sigma<&2, &2, String, _ => String>>) -> String:
  match xs:
    case Nil{}:
      ""
    case (+k, +v) <> t:
      k ++ "\u{1f}" ++ v ++ "\u{1e}" ++ Mm.strs(t)

def Mm.flags(xs: List<&2, Sigma<&2, &2, String, _ => Bool>>) -> String:
  match xs:
    case Nil{}:
      ""
    case (+k, +v) <> t:
      k ++ Bool.pick(String, v, "+", "-") ++ Mm.flags(t)

# info the main area never reads, or reads only as part of the key
# otherwise: the clock (now is in the key), the caret's timing (its phase,
# caret.on, is kept), the cats', the frame's own bookkeeping, the hover
# and the performance overlay (both drawn over the whole frame), a page's
# frames (shown only in the viewer and a bot's view: neither is kept)
def Mm.volatile(+k: String) -> Bool:
  Bool.or(Nat.is_lt(C.Codec.pos(["clock", "act.at", "cat.due", "cat.clock", "caret.due", "caret.at", "caret.sig", "frame.hub", "frame.late", "hover", "perf.hud"], k), 11n),
    Bool.or(String.starts_with(k, "img:shot:"), String.starts_with(k, "shot.")))

def Mm.info.k(skip: Bool, +k: String, +v: String, +rest: String) -> String:
  match skip:
    case True{}:
      rest
    case False{}:
      k ++ "\u{1f}" ++ v ++ "\u{1e}" ++ rest

def Mm.info(xs: List<&2, Sigma<&2, &2, String, _ => String>>) -> String:
  match xs:
    case Nil{}:
      ""
    case (+k, +v) <> t:
      Mm.info.k(Mm.volatile(k), k, v, Mm.info(t))

def Mm.hit(h: N.Hit) -> String:
  match h:
    case N.Hit{x0, y0, x1, y1, a, v}:
      U32.show(x0) ++ "," ++ U32.show(y0) ++ "," ++ U32.show(x1) ++ "," ++ U32.show(y1) ++ "," ++ a ++ "," ++ v

def Mm.b(b: Bool) -> String:
  Bool.pick(String, b, "1", "0")

# the main area's right edge (Lay.frame.u's: half the window with the
# viewer open)
def Mm.x1(+pa: Bool, +w: U32) -> U32:
  Bool.pick(U32, pa, (264 + U32.shr((w - 264 : U32)) : U32), w)

def Mm.x1.of(+n: N.Nui) -> U32:
  Mm.x1(U.Ui.panel(N.Nui.ui(n)), N.Nui.width(n))

# The clock in the main area: a subagent's row hides a day after it ends
# (to the second), and the header says whether the thread is snoozed; else
# nothing there moves with it. So the second counts while the thread has
# children or its own background rows, else the minute and the snooze.
def Mm.subs(+st: M.State, +sel: String, rels: List<&2, String>) -> Bool:
  Bool.or(Bool.not(List.is_empty(&2, String, rels)), Bool.or(Bool.not(String.is_empty(M.Setting.get(st, "bg." ++ sel, ""))), Bool.not(String.is_empty(M.Setting.get(st, "watch." ++ sel, "")))))

def Mm.when(+st: M.State, +sel: String, +now: Nat, +rels: List<&2, String>) -> String:
  Bool.pick(String, Mm.subs(st, sel, rels), "s" ++ Nat.show(now), "m" ++ Nat.show(Nat.div(now, 60n)))
    ++ Bool.pick(String, M.Snooze.on(now, U.Side.until(st, sel)), "z", "")

# the main area is memoized only for a thread's view: not the settings,
# not the empty window, not with a terminal anywhere (embedded screens read
# the terminals' state, which no touch follows)
def Mm.memo.ok(+op: Map<&2, Bool>, +sel: String, +tr: Map<&2, VT.Vt>) -> Bool:
  Bool.and(Bool.and(Bool.not(U.Flag.get(op, "settings")), Bool.not(String.is_empty(sel))), List.is_empty(&2, String, Map.keys(&2, VT.Vt, tr)))

def Mm.key.go(+n: N.Nui, +t: TouchK, +rels: List<&2, String>) -> String:
  match n:
    case N.Nui{U.Ui{+st, +sel, +dr, +live, +op, on, +now, ad, pa, v, rid, w, er, note, +nf, +ob, _}, +ww, +hh, _, _, _, sc, ca, fo, path, +hi, _, _}:
      "s" ++ Mm.stamps(sel <> rels, t) ++ "|lang" ++ L.TL.locale(N.Nui.ui(n))
        ++ "|g" ++ Nat.show(TouchK.g(t)) ++ "|t" ++ Mm.when(st, sel, now, rels) ++ "|w" ++ U32.show(ww) ++ "," ++ U32.show(hh) ++ "," ++ U32.show(sc) ++ "," ++ Nat.show(ca) ++ "," ++ fo ++ "," ++ path
        ++ "|x" ++ U32.show(Mm.x1(pa, ww)) ++ "|cs" ++ N.Cs.region(hi) ++ "|ch" ++ Mm.hit(L.Comp.hit(hi))
        ++ "|u" ++ Mm.b(on) ++ Mm.b(ad) ++ Mm.b(pa) ++ Mm.b(w) ++ "," ++ v ++ "," ++ Nat.show(rid) ++ "," ++ er ++ "," ++ note
        ++ "|f" ++ Mm.flags(Map.to_list(&2, Bool, op)) ++ "|d" ++ Mm.strs(Map.to_list(&2, String, dr)) ++ "|o" ++ Mm.strs(Map.to_list(&2, String, ob))
        ++ "|l" ++ U.Str.get(live, sel) ++ "|i" ++ Mm.info(Map.to_list(&2, String, nf))

def Mm.key.k(ok: Bool, +n: N.Nui, +t: TouchK, +rels: List<&2, String>) -> String:
  match ok:
    case False{}:
      ""
    case True{}:
      Mm.key.go(n, t, rels)

# the main area's key ("": not memoized); rels: the open thread's parent
# and children (Mm.rels)
def Mm.key(+n: N.Nui, +t: TouchK, +rels: List<&2, String>) -> String:
  match n:
    case N.Nui{U.Ui{_, +sel, _, _, +op, _, _, _, _, _, _, _, _, _, _, _, +tr}, _, _, _, _, _, _, _, _, _, _, _, _}:
      Mm.key.k(Mm.memo.ok(op, sel, tr), n, t, rels)

# The memo
# --------
# key: the main area's; rk: the open thread with its own last touch and
# the last change to whose parent or child any thread is otherwise (r):
# a delegation or a launch touches both ends, so rels, found by walking
# every task, is found again only when rk changes

type MainM is Data:
  MainM{key: String, rk: String, rels: List<&2, String>, out: L.Out}

def Mm.rk(+n: N.Nui, +t: TouchK) -> String:
  U.Ui.sel(N.Nui.ui(n)) ++ "|" ++ Nat.show(TouchK.at(t, U.Ui.sel(N.Nui.ui(n)))) ++ "|" ++ Nat.show(TouchK.r(t))

def Mm.rels.of(+n: N.Nui) -> List<&2, String>:
  match n:
    case N.Nui{U.Ui{+st, +sel, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}, _, _, _, _, _, _, _, _, _, _, _, _}:
      List.concat(&2, String, [[U.Tasks.up(st, sel)], Mm.children(U.Tasks.of(st, sel)), M.Launch.of(st, sel)])

def Mm.rels.k(same: Bool, ms: List<&2, MainM>, +n: N.Nui) -> List<&2, String>:
  match same ms:
    case True{} MainM{_, _, rs, _} <> _:
      rs
    case _ _:
      Mm.rels.of(n)

def MainM.rk.is(+rk: String, ms: List<&2, MainM>) -> Bool:
  match ms:
    case Nil{}:
      False{}
    case MainM{_, +k, _, _} <> _:
      String.eq(k, rk)

# the open thread's parent and children, the memo's while rk holds
def Mm.rels(+rk: String, +ms: List<&2, MainM>, +n: N.Nui) -> List<&2, String>:
  Mm.rels.k(MainM.rk.is(rk, ms), ms, n)

def MainM.same(+key: String, ms: List<&2, MainM>) -> Bool:
  match ms:
    case Nil{}:
      False{}
    case MainM{+k, _, _, _} <> _:
      Bool.and(Bool.not(String.is_empty(key)), String.eq(k, key))

def MainM.out(ms: List<&2, MainM>) -> L.Out:
  match ms:
    case Nil{}:
      L.Out.none()
    case MainM{_, _, _, o} <> _:
      o

# the main area as Lay.frame.u lays it out (Lay.main.m with none given)
def Mm.lay(+ty: L.Ty, +memo: L.TLMemo, +n: N.Nui) -> L.Out:
  L.Lay.main(ty, memo, L.Lay.shrink(n, L.Lay.term_h(n)), 264, Mm.x1.of(n))

def Mm.main.k(hit: Bool, +key: String, +rk: String, +rels: List<&2, String>, ms: List<&2, MainM>, +ty: L.Ty, +memo: L.TLMemo, +n: N.Nui) -> MainM:
  match hit:
    case True{}:
      MainM{key, rk, rels, MainM.out(ms)}
    case False{}:
      MainM{key, rk, rels, Mm.lay(ty, memo, n)}

def Mm.main.s(+key: String, +rk: String, +rels: List<&2, String>, +ms: List<&2, MainM>, +ty: L.Ty, +memo: L.TLMemo, +n: N.Nui) -> MainM:
  Mm.main.k(MainM.same(key, ms), key, rk, rels, ms, ty, memo, n)

def Mm.main.r(+rk: String, +rels: List<&2, String>, +ms: List<&2, MainM>, +ty: L.Ty, +memo: L.TLMemo, +n: N.Nui, +t: TouchK) -> MainM:
  Mm.main.s(Mm.key(n, t, rels), rk, rels, ms, ty, memo, n)

def Mm.main.q(+rk: String, +ms: List<&2, MainM>, +ty: L.Ty, +memo: L.TLMemo, +n: N.Nui, +t: TouchK) -> MainM:
  Mm.main.r(rk, Mm.rels(rk, ms, n), ms, ty, memo, n, t)

# the main area: the memo's when its key is this frame's, else laid out
def Mm.main(+ms: List<&2, MainM>, +ty: L.Ty, +memo: L.TLMemo, +n: N.Nui, +t: TouchK) -> MainM:
  Mm.main.q(Mm.rk(n, t), ms, ty, memo, n, t)

# a fresh main area kept as the memo (memo_replay)
def Mm.fresh(+ms: List<&2, MainM>, o: L.Out, +n: N.Nui, +t: TouchK) -> MainM:
  MainM{Mm.key(n, t, Mm.rels(Mm.rk(n, t), ms, n)), Mm.rk(n, t), Mm.rels(Mm.rk(n, t), ms, n), o}

# the memo says the main area is unchanged
def Mm.hits(+ms: List<&2, MainM>, +n: N.Nui, +t: TouchK) -> Bool:
  MainM.same(Mm.key(n, t, Mm.rels(Mm.rk(n, t), ms, n)), ms)

def MainM.key(m: MainM) -> String:
  match m:
    case MainM{k, _, _, _}:
      k

def MainM.keep(m: MainM) -> List<&2, MainM>:
  match m:
    case MainM{+k, rk, rs, o}:
      Bool.pick(List<&2, MainM>, String.is_empty(k), Nil{}, [MainM{k, rk, rs, o}])

# The sidebar's memo
# ------------------
# Its body (L.Lay.sidebar.a: the threads, the links, the bots and rooms)
# reads the whole state, so any hub message may change it: it is kept only
# while none came (TouchK's count) and the window's fields it reads are
# the same: a key typed, the thread scrolled, the pointer moved. The clock
# counts to the second (a snooze ends to the second). The drafts are not
# in it: the sidebar draws none (memo_replay types into the composer and
# checks each kept sidebar against a fresh one).

def TouchK.n(+t: TouchK) -> Nat:
  match t:
    case TouchK{n, _, _, _}:
      n

# the caret, unless it is the composer's (in the main area, never drawn
# in the sidebar): a key typed there keeps the sidebar's memo
def Sm.caret(+fo: String, +ca: Nat) -> String:
  Bool.pick(String, String.eq(fo, "composer"), "-", Nat.show(ca))

def Sm.key(+n: N.Nui, +t: TouchK) -> String:
  match n:
    case N.Nui{U.Ui{_, +sel, _, _, +op, on, now, ad, pa, v, rid, w, er, note, +nf, +ob, _}, +ww, +hh, _, _, sd, _, ca, +fo, path, _, _, _}:
      "n" ++ Nat.show(TouchK.n(t)) ++ "|" ++ sel ++ "|lang" ++ L.TL.locale(N.Nui.ui(n)) ++ "|t" ++ Nat.show(now) ++ "|w" ++ U32.show(ww) ++ "," ++ U32.show(hh) ++ "," ++ U32.show(sd) ++ "," ++ Sm.caret(fo, ca) ++ "," ++ fo ++ "," ++ path
        ++ "|u" ++ Mm.b(on) ++ Mm.b(ad) ++ Mm.b(pa) ++ Mm.b(w) ++ "," ++ v ++ "," ++ Nat.show(rid) ++ "," ++ er ++ "," ++ note
        ++ "|f" ++ Mm.flags(Map.to_list(&2, Bool, op)) ++ "|o" ++ Mm.strs(Map.to_list(&2, String, ob))
        ++ "|i" ++ Mm.info(Map.to_list(&2, String, nf))

type SideM is Data:
  SideM{key: String, out: L.Out}

def SideM.same(+key: String, ms: List<&2, SideM>) -> Bool:
  match ms:
    case Nil{}:
      False{}
    case SideM{+k, _} <> _:
      String.eq(k, key)

def SideM.out(ms: List<&2, SideM>) -> L.Out:
  match ms:
    case Nil{}:
      L.Out.none()
    case SideM{_, o} <> _:
      o

# The sidebar's index
# -------------------
# core's Side.ix walks every thread, task and setting; the sidebar and the
# Status plane's counts each made it every frame. The window keeps one
# (IxK) and brings it up to date: the same while no hub message came, made
# again whole after a change of all, of whose child a thread is (r), or a
# setting applied here ("local.touch"), else only the threads touched
# since are looked at again: their entries in place (Ix.one), or the whole
# index again when one came, went or moved. test/native/memo_replay.bend
# checks each against Side.ix on a real log.

type IxK is Data:
  IxK{n: Nat, lt: String, ix: U.SIx}

def IxK.ix(k: IxK) -> U.SIx:
  match k:
    case IxK{_, _, x}:
      x

def Ix.full(+u: U.Ui, +n: Nat) -> IxK:
  IxK{n, U.Ui.info(u, "local.touch"), U.Side.ix(U.Ui.state(u))}

# (the recursion made once, outside the choice: a Bool.pick with it in both
# branches does the rest twice for every element)
def Ix.keep.s(keep: Bool, +k: String, rest: List<&2, String>) -> List<&2, String>:
  match keep:
    case True{}:
      k <> rest
    case False{}:
      rest

def Ix.keep.a(keep: Bool, a: M.Ask, rest: List<&2, M.Ask>) -> List<&2, M.Ask>:
  match keep:
    case True{}:
      a <> rest
    case False{}:
      rest

# the threads touched after message n0
def Ix.since(xs: List<&2, Sigma<&2, &2, String, _ => Nat>>, +n0: Nat) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case (+k, +v) <> +t:
      Ix.keep.s(Nat.is_gt(v, n0), k, Ix.since(t, n0))

def Ix.has(ts: List<&2, M.Thread>, +id: String) -> Bool:
  match ts:
    case Nil{}:
      False{}
    case M.Thread{+i, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} <> t:
      Bool.or(String.eq(i, id), Ix.has(t, id))

def Ix.swap.k(same: Bool, t: M.Thread, +r: M.Thread, rest: List<&2, M.Thread>) -> List<&2, M.Thread>:
  match same:
    case True{}:
      r <> rest
    case False{}:
      t <> rest

# the list with the thread of r's id replaced by r
def Ix.swap(ts: List<&2, M.Thread>, +r: M.Thread) -> List<&2, M.Thread>:
  match ts:
    case Nil{}:
      Nil{}
    case M.Thread{+i, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de} <> t:
      Ix.swap.k(String.eq(i, M.Thread.id(r)), M.Thread{i, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de}, r, Ix.swap(t, r))

def Ix.list.k(r: Map<&2, List<&2, M.Thread>> & List<&2, M.Thread>) -> List<&2, M.Thread>:
  (_, xs) = r
  xs

def Ix.asks.k(r: Map<&2, List<&2, M.Ask>> & List<&2, M.Ask>) -> List<&2, M.Ask>:
  (_, xs) = r
  xs

def Ix.mine(as: List<&2, M.Ask>, +id: String) -> List<&2, M.Ask>:
  match as:
    case Nil{}:
      Nil{}
    case M.Ask{i, +th, k, t, d, o, op, an} <> +rest:
      Ix.keep.a(String.eq(th, id), M.Ask{i, th, k, t, d, o, op, an}, Ix.mine(rest, id))

def Ix.asks.put(xs: List<&2, M.Ask>, +id: String, m: Map<&2, List<&2, M.Ask>>) -> Map<&2, List<&2, M.Ask>>:
  match xs:
    case Nil{}:
      Map.del(&2, List<&2, M.Ask>, m, id)
    case +a <> t:
      Map.set(&2, List<&2, M.Ask>, m, id, a <> t)

# a thread's open asks, as Side.ix files them
def Ix.asks(+st: M.State, +id: String, m: Map<&2, List<&2, M.Ask>>) -> Map<&2, List<&2, M.Ask>>:
  Ix.asks.put(Ix.asks.k(Map.get(List<&2, M.Ask>, Nil{}, U.SIx.asks.go(List.reverse(&2, M.Ask, Ix.mine(M.Asks.all(st), id)), Map.new(&2, List<&2, M.Ask>)), id)), id, m)

def Ix.yes(r: Map<&2, String> & Bool) -> Bool:
  (_, b) = r
  b

def Ix.yes.t(r: Map<&2, M.Thread> & Bool) -> Bool:
  (_, b) = r
  b

def Ix.sg(s: M.State) -> Map<&2, String>:
  match s:
    case M.State{_, _, _, _, _, sg, _, _, _, _, _}:
      sg

# a thread's own rows, as Work.rows.map keeps them (an entry while it has
# a "bg." or "watch." setting at all)
def Ix.work(+st: M.State, +id: String, +m: Map<&2, Nat>) -> Map<&2, Nat>:
  Bool.pick(Map<&2, Nat>, Bool.or(Ix.yes(Map.has(&2, String, Ix.sg(st), "bg." ++ id)), Ix.yes(Map.has(&2, String, Ix.sg(st), "watch." ++ id))),
    Map.set(&2, Nat, m, id, M.Work.rows(st, id)), Map.del(&2, Nat, m, id))

type IxAcc is Data:
  IxAcc{ok: Bool, by: Map<&2, List<&2, M.Thread>>, asks: Map<&2, List<&2, M.Ask>>, work: Map<&2, Nat>}

def IxAcc.no(a: IxAcc) -> IxAcc:
  match a:
    case IxAcc{_, b, x, w}:
      IxAcc{False{}, b, x, w}

type Ix2 is Data:
  Ix2{ok: Bool, by: Map<&2, List<&2, M.Thread>>}

# a thread's place: where it is filed (its project's list, unless it is a
# delegated child) must be where it was; then it is put in again in place
def Ix.place.k(kid: Bool, there: Bool, r: M.Thread, +p: String, +by: Map<&2, List<&2, M.Thread>>, ok: Bool) -> Ix2:
  match kid there:
    case True{} True{}:
      Ix2{False{}, by}
    case True{} False{}:
      Ix2{ok, by}
    case False{} True{}:
      Ix2{ok, Map.set(&2, List<&2, M.Thread>, by, p, Ix.swap(Ix.list.k(Map.get(List<&2, M.Thread>, Nil{}, by, p)), r))}
    case False{} False{}:
      Ix2{False{}, by}

def Ix.project(t: M.Thread) -> String:
  match t:
    case M.Thread{_, p, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      p

def Ix.place(m: Maybe<&2, M.Thread>, +kids: Map<&2, Bool>, +id: String, +by: Map<&2, List<&2, M.Thread>>, ok: Bool) -> Ix2:
  match m:
    case Some{+r}:
      Ix.place.k(U.Flag.get(kids, id), Ix.has(Ix.list.k(Map.get(List<&2, M.Thread>, Nil{}, by, Ix.project(r))), id), r, Ix.project(r), by, ok)
    case None{}:
      Ix2{False{}, by}

def Ix.one.k(p: Ix2, +st: M.State, +id: String, x: Map<&2, List<&2, M.Ask>>, w: Map<&2, Nat>) -> IxAcc:
  match p:
    case Ix2{ok, b}:
      IxAcc{ok, b, Ix.asks(st, id, x), Ix.work(st, id, w)}

def Ix.thread.k(r: Map<&2, M.Thread> & M.Thread, has: Bool) -> Maybe<&2, M.Thread>:
  (_, t) = r
  Bool.pick(Maybe<&2, M.Thread>, has, Some{t}, None{})

def Ix.thread(+st: M.State, +id: String) -> Maybe<&2, M.Thread>:
  match st:
    case M.State{_, +ts, _, _, _, _, _, _, _, _, _}:
      Ix.thread.k(Map.get(M.Thread, M.Thread.blank(id), ts, id), Ix.yes.t(Map.has(&2, M.Thread, ts, id)))

def Ix.one(a: IxAcc, +st: M.State, +kids: Map<&2, Bool>, +id: String) -> IxAcc:
  match a:
    case IxAcc{ok, b, x, w}:
      Ix.one.k(Ix.place(Ix.thread(st, id), kids, id, b, ok), st, id, x, w)

def Ix.all(ids: List<&2, String>, a: IxAcc, +st: M.State, +kids: Map<&2, Bool>) -> IxAcc:
  match ids:
    case Nil{}:
      a
    case +id <> t:
      Ix.all(t, Ix.one(a, st, kids, id), st, kids)

def Ix.inc.k(a: IxAcc, +u: U.Ui, +n: Nat, +lt: String) -> IxK:
  match a:
    case IxAcc{True{}, b, x, w}:
      IxK{n, lt, U.SIx{b, x, M.Work.kids.map(U.Ui.state(u)), w}}
    case IxAcc{False{}, _, _, _}:
      Ix.full(u, n)

def Ix.inc(ix: U.SIx, +ids: List<&2, String>, +u: U.Ui, +n: Nat, +lt: String) -> IxK:
  match ix:
    case U.SIx{b, x, _, w}:
      Ix.inc.k(Ix.all(ids, IxAcc{True{}, b, x, w}, U.Ui.state(u), U.Kids.set(U.Ui.state(u))), u, n, lt)

def Ix.up.k(i: Nat, k: IxK, +t: TouchK, +u: U.Ui) -> IxK:
  match i k:
    case 0n _:
      k
    case 1n _:
      Ix.full(u, TouchK.n(t))
    case _ IxK{n0, lt, ix}:
      Ix.inc(ix, Ix.since(Map.to_list(&2, Nat, TouchK.m(t)), n0), u, TouchK.n(t), lt)

def Ix.mode(+n0: Nat, +lt0: String, +t: TouchK, +u: U.Ui) -> Nat:
  Bool.pick(Nat, Bool.not(String.eq(lt0, U.Ui.info(u, "local.touch"))), 1n,
    Bool.pick(Nat, Bool.or(Nat.is_gt(TouchK.g(t), n0), Nat.is_gt(TouchK.r(t), n0)), 1n,
      Bool.pick(Nat, Nat.is_eq(TouchK.n(t), n0), 0n, 2n)))

def IxK.n(k: IxK) -> Nat:
  match k:
    case IxK{n, _, _}:
      n

def IxK.lt(k: IxK) -> String:
  match k:
    case IxK{_, l, _}:
      l

# the index for this frame, from the last frame's
def Ix.up(ks: List<&2, IxK>, +t: TouchK, +u: U.Ui) -> IxK:
  match ks:
    case Nil{}:
      Ix.full(u, TouchK.n(t))
    case +k <> _:
      Ix.up.k(Ix.mode(IxK.n(k), IxK.lt(k), t, u), k, t, u)

def Ix.ids.n(ts: List<&2, M.Thread>, +acc: Nat) -> Nat:
  match ts:
    case Nil{}:
      acc
    case M.Thread{+i, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} <> t:
      Ix.ids.n(t, Nat.add(acc, String.length(i)))

# The index is made in full each frame (its lists walked): one left to be
# made later would keep the last frame's state and be built on, unmade,
# frame after frame
def Ix.lens(xs: List<&2, Sigma<&2, &2, String, _ => List<&2, M.Thread>>>, +acc: Nat) -> Nat:
  match xs:
    case Nil{}:
      acc
    case (_, v) <> t:
      Ix.lens(t, Nat.add(acc, Ix.ids.n(v, 0n)))

def IxK.force(k: IxK) -> Nat:
  match k:
    case IxK{n, lt, U.SIx{by, a, kd, w}}:
      Nat.add(Nat.add(n, Ix.lens(Map.to_list(&2, List<&2, M.Thread>, by), 0n)),
        Nat.add(List.length(&2, String, Map.keys(&2, List<&2, M.Ask>, a)), Nat.add(List.length(&2, String, Map.keys(&2, Nat, kd)), List.length(&2, String, Map.keys(&2, Nat, w)))))
