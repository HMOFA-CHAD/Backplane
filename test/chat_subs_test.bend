import Base
import ./subagents_test.bend as F
import ./side_rows_test.bend as E
import ./native/chat_subs_probe.bend as FP
import ../src/core/model.bend as M
import ../src/core/client.bend as U
import ../src/core/subs.bend as SB
import ../src/app/layout.bend as L
import ../src/app/nui.bend as N
import ../src/app/bots.bend as B
import ../src/app/cats.bend as CA
import ../src/app/mm.bend as MM
import ./index_rename_test.bend as IX

def check(ok: Bool, name: String) -> IO(Unit):
  match ok:
    case True{}: IO.print("ok " ++ name)
    case False{}: IO.die(Unit, 1, "FAIL " ++ name)

def state_at(k: Nat) -> M.State:
  match k:
    case 0n: M.State.empty()
    case 1n: F.state(F.tree())
    case 2n: F.recent.tasks()
    case 3n: F.launch.ask()
    case 4n: F.state(F.started())
    case 5n: F.state(F.progressed())
    case _: F.state(F.ended())

def selected(k: Nat) -> String:
  match k:
    case 0n: ""
    case 1n: "t0"
    case 2n: "t0"
    case 3n: "t0"
    case _: "t100-1"

def rowcase(+k: Nat, +now: Nat) -> IO(Unit):
  do IO<Unit>:
    +st : M.State = state_at(k)
    +info : Map<&2, String> = Map.new(&2, String)
    check(String.eq(FP.rows(SB.Subs.rows(st, info, selected(k), now)), FP.rows(SB.Subs.rows.ix(st, info, selected(k), now, U.Side.ix(st)))), "complete rows " ++ Nat.show(k) ++ " clock " ++ Nat.show(now))
    check(String.eq(FP.rows(SB.Subs.rows(st, info, selected(k), now)), FP.rows(SB.Subs.rows.at(st, info, selected(k), now, Nil{}))), "missing-index fresh fallback " ++ Nat.show(k))

def rowcases(ks: List<&2, Nat>, +now: Nat) -> IO(Unit):
  match ks:
    case Nil{}: IO.pure(Unit, Unit{})
    case k <> rest:
      do IO<Unit>:
        rowcase(k, now)
        rowcases(rest, now)

def bot_ui() -> U.Ui:
  U.Ui.scratch_set(U.Act.ui(U.Ui.act(U.Ui.fold(List.append(&2, M.Change, F.tree(),
    [M.BotSet{"b1", "Test bot", "t0", 1n, "", 100n}]), U.Ui.init(110n)), "bot", "b1")), "@btab", "chat")

def is_present(m: Maybe<&2, L.Out>) -> Bool:
  match m:
    case Some{_}: True{}
    case None{}: False{}

def framecase(+u: U.Ui, +w: U32, +h: U32, +label: String) -> IO(Unit):
  do IO<Unit>:
    +n : N.Nui = N.Nui.init(u, w, h)
    +ty : L.Ty = L.Ty.with_loc(L.Ty.none(), U.Lang.loc(u))
    +m : L.TLMemo = L.TL.memos.now(L.Lay.memos(ty, n, Nil{}))
    +ws : Map<&2, B.PW> = B.Bv.wraps.none()
    check(E.same.out(L.Lay.thread.at(ty, m, n, 264, w, 34), L.Lay.thread.at.ix(ty, m, n, 264, w, 34, [U.Side.ix(U.Ui.state(u))])), "complete chat ops/hits " ++ label)
    check(is_present(B.Bv.main.w(ty, m, CA.Cats.none(), ws, n)), "bot view actually selected " ++ label)
    check(E.same.out(Maybe.default(&2, L.Out, B.Bv.main.w(ty, m, CA.Cats.none(), ws, n), L.Out.none()),
      Maybe.default(&2, L.Out, B.Bv.main.w.ix(ty, m, CA.Cats.none(), ws, n, [U.Side.ix(U.Ui.state(u))]), L.Out.none())), "bot header/body ops/hits " ++ label)

# The real frame supplies MM.Ix.up rather than reconstructing Side.ix.
# Exercise that exact delivery boundary after child/debt transitions.
def incremental(+cs: List<&2, M.Change>, +label: String) -> IO(Unit):
  do IO<Unit>:
    +u0 : U.Ui = bot_ui()
    +u : U.Ui = U.Ui.fold(cs, u0)
    +tc : MM.TouchK = MM.TouchK.msg(IX.changes(cs), MM.TouchK.none())
    +ix : U.SIx = MM.IxK.ix(MM.Ix.up([MM.Ix.full(u0, 0n)], tc, u))
    +n : N.Nui = N.Nui.init(u, 1400, 900)
    +ty : L.Ty = L.Ty.none()
    +m : L.TLMemo = L.TL.memos.now(L.Lay.memos(ty, n, Nil{}))
    check(String.eq(IX.Fp.ix(ix), IX.Fp.ix(U.Side.ix(U.Ui.state(u)))), "incremental index fresh " ++ label)
    check(String.eq(FP.rows(SB.Subs.rows(U.Ui.state(u), U.Ui.infos(u), U.Ui.sel(u), U.Side.now(u))),
      FP.rows(SB.Subs.rows.ix(U.Ui.state(u), U.Ui.infos(u), U.Ui.sel(u), U.Side.now(u), ix))), "incremental rows fresh " ++ label)
    check(E.same.out(L.Lay.thread.at(ty, m, n, 264, 1400, 34), L.Lay.thread.at.ix(ty, m, n, 264, 1400, 34, [ix])), "incremental chat ops/hits " ++ label)

def main() -> IO(Unit):
  do IO<Unit>:
    rowcases([0n, 1n, 2n, 3n, 4n, 5n, 6n], 110n)
    rowcases([1n, 2n, 3n, 6n], 100000n)
    framecase(bot_ui(), 1400, 900, "wide")
    framecase(U.Ui.scratch_set(bot_ui(), "@lang.tag", "ja"), 900, 600, "locale narrow")
    framecase(U.Ui.info_set(bot_ui(), "fold:subs.done:t0", "1"), 1400, 900, "finished group open")
    framecase(U.Ui.info_set(bot_ui(), "pane:subs:t0", "1"), 1400, 900, "panel scrolled")
    incremental([M.ThreadRenamed{"t1", "Renamed child", 111n}], "rename")
    incremental([M.TaskStateSet{"k1", M.TaskDone{}, "done", 111n}], "task done")
    incremental([M.AskOpened{"a1", "t1", "approval", "", "Allow?", "", 111n}], "approval")
    incremental([M.AskOpened{"a1", "t1", "input", "", "Which?", "", 111n}, M.AskClosed{"a1", "answer", 112n}], "ask closed")
    incremental([M.ThreadCreated{"extra", "p1", "New child", M.Local{}, "", "", "codex", "", 111n}, M.ThreadLaunched{"extra", "t0", False{}, 111n}], "new launch")
    incremental([M.SettingSet{"global.debt", "1", 111n}, M.ThreadRenamed{"t1", "After debt", 112n}], "global debt")
    incremental([M.ThreadDeleted{"t1", 111n}], "deleted child")
    IO.print("PASS exact subagent index reuse and complete chat output")
