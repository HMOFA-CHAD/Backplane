import Base
import ./check.bend as C
import ../src/core/client.bend as U
import ../src/core/signal.bend as SG
import ../src/core/model.bend as M
import ../src/core/json.bend as J
import ../src/web/app.bend as A
import ../src/web/presentation.bend as WP

def state() -> M.State:
  M.State.replay([M.ProjectCreated{"p", "Board", "/tmp/signal-revision", 1n},
    M.ThreadCreated{"self", "p", "Here", M.Local{}, "", "", "codex", "", 2n},
    M.ThreadCreated{"other", "p", "Other", M.Local{}, "", "", "codex", "", 3n},
    M.TurnChanged{"other", M.Running{}, 4n}], M.State.empty())

def yes(b: Bool) -> String:
  Bool.pick(String, b, "yes", "no")

def same(+a: String, +b: String) -> String:
  yes(C.Check.same(a, b))

def ui(st: M.State, clock: Nat) -> U.Ui:
  U.Ui.info_set(U.Ui.scratch_set(U.Ui.flag_on(U.Ui.select.k(U.Ui.adopt.raw(U.Ui.init(clock), st), "self"), "settings"), "self", "PRIVATE 日本語 IME draft"), "local.mailroom", "on")

def equal(+u: U.Ui, +reuse: Bool) -> String:
  same(J.Json.show(WP.Node.write(A.view_sidebar_indexed(u, reuse, SG.Signal.index(U.Ui.state(u))))), J.Json.show(WP.Node.write(A.view_sidebar(u, reuse))))

def changed(+e: M.Change) -> String:
  +st = M.State.apply(state(), e)
  equal(U.Ui.online(ui(st, 11n), True{}), False{})

def values(xs: List<&2, Sigma<&2, &2, String, _ => Nat>>) -> List<&2, J.KV>:
  match xs:
    case Nil{}: Nil{}
    case (k, n) <> rest: J.KV{k, J.Json.nat(n)} <> values(rest)

def work(ix: U.SIx) -> String:
  match ix:
    case U.SIx{_, _, _, m}: J.Json.show(J.Json.obj(values(Map.to_list(&2, Nat, m))))

def index_equal(+online: Bool) -> String:
  +u = U.Ui.online(ui(state(), 11n), online)
  +ix = U.Side.ix(state())
  same(work(U.Side.signals.ix.given(ix, u, SG.Signal.index(state()))), work(U.Side.signals.ix(ix, U.Side.with_signals(u))))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("online numeric display map equals parsed reference", index_equal(True{}), "yes")
    C.Check.str("offline numeric display map equals parsed reference", index_equal(False{}), "yes")
    C.Check.str("full project page is exact", equal(U.Ui.online(ui(state(), 11n), True{}), False{}), "yes")
    C.Check.str("full offline page is exact", equal(U.Ui.online(ui(state(), 11n), False{}), False{}), "yes")
    C.Check.str("full Active page and keyboard destinations exact", changed(M.SettingSet{"sidebar.view", "active", 5n}), "yes")
    C.Check.str("full approval and count exact", changed(M.AskOpened{"ask", "other", "approval", "tool", "Allow", "", 5n}), "yes")
    C.Check.str("full owned-work presentation exact", changed(M.WorkSet{"self", "watch", "w\twatching\t\tbuild\twatch", 5n}), "yes")
    C.Check.str("settled presentation exact", changed(M.ThreadSettled{"self", False{}, 5n}), "yes")
    C.Check.str("search projection exact", equal(U.Ui.scratch_set(ui(state(), 11n), "@f.pq", "Other"), False{}), "yes")
    C.Check.str("history projection exact", equal(U.Ui.flag_on(ui(state(), 11n), "conversation-history"), False{}), "yes")
    C.Check.str("retained sidebar placeholder exact", equal(ui(state(), 11n), True{}), "yes")
    C.Check.str("reserved unknown info falls back exactly", equal(U.Ui.info_set(ui(state(), 11n), "@signal:ghost", "3"), False{}), "yes")
    C.Check.str("already decorated input falls back exactly", equal(U.Side.with_signals(ui(state(), 11n)), False{}), "yes")
    C.Check.str("reserved key disables direct path", yes(SG.Signal.info.raw(["models", "@signal:ghost"])), "no")
    C.Check.str("ordinary info permits direct path", yes(SG.Signal.info.raw(["models", "fold:one", "@signal.online"])), "yes")
