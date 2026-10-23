import Base
import ./check.bend as C
import ../src/core/client.bend as U
import ../src/core/model.bend as M

def base() -> M.State:
  M.State.replay([M.ProjectCreated{"scratch", "Scratch", "/tmp/old", 0n},
    M.ThreadCreated{"history", "scratch", "Old chat", M.Local{}, "", "", "codex", "", 1n},
    M.ThreadCreated{"child", "p1", "Child", M.Local{}, "", "", "codex", "", 20n}, M.ThreadParentSet{"child", "t1", 21n}], U.Side.demo.work())

def ui(st: M.State) -> U.Ui:
  U.Ui.adopt.raw(U.Ui.init(25n), st)

def selected(st: M.State, id: String) -> U.Ui:
  U.Ui.select.k(ui(st), id)

def same(+u: U.Ui) -> String:
  +ix = U.Side.ix(U.Ui.state(u))
  Bool.pick(String, Bool.and(String.eq(String.join(U.Side.projects(u), ","), String.join(U.Side.projects.ix(u, ix), ",")),
    String.eq(String.join(U.Side.here(u), ","), String.join(U.Side.here.ix(u, ix), ","))), "same", "DIFFERENT")

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("indexed hint destinations preserve project folds", same(selected(base(), "t1")), "same")
    C.Check.str("indexed hints preserve expanded subthreads", same(selected(M.State.apply(base(), M.SettingSet{"thread.tree.t1", "1", 22n}), "t1")), "same")
    C.Check.str("indexed hints preserve explicit collapse and deep selection", same(selected(M.State.apply(base(), M.SettingSet{"thread.tree.t1", "0", 22n}), "child")), "same")
    C.Check.str("indexed hints preserve active mode ordering", same(selected(M.State.apply(base(), M.SettingSet{"sidebar.view", "active", 22n}), "t1")), "same")
    C.Check.str("indexed hints preserve active settled expansion", same(U.Ui.flag_on(selected(M.State.apply(base(), M.SettingSet{"sidebar.view", "active", 22n}), "t3"), "active-settled")), "same")
    C.Check.str("indexed hints preserve project search", same(U.Ui.scratch_set(selected(base(), "t1"), "@f.pq", "One")), "same")
    C.Check.str("indexed hints preserve active tree search", same(U.Ui.scratch_set(selected(M.State.apply(base(), M.SettingSet{"sidebar.view", "active", 22n}), "child"), "@f.pq", "Child")), "same")
    C.Check.str("indexed hints preserve legacy history targets", same(U.Ui.flag_on(selected(base(), "history"), "conversation-history")), "same")
    C.Check.str("indexed hints preserve other current project", same(selected(base(), "t3")), "same")
