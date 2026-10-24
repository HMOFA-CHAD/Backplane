import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/signal.bend as G
import ../src/core/client.bend as U
import ../src/core/json.bend as J
import ../src/core/thin.bend as T
import ../src/core/thin-live.bend as L
import ../src/core/thin-pace.bend as P
import ../src/server/thin-signals.bend as K
import ../src/server/thin-actor.bend as A
import ../src/server/thin-view.bend as V

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

def request() -> J.Json:
  J.Json.obj([J.KV{"target", V.Target.json("thread", "self")}, J.KV{"action", J.Str{"flag"}}, J.KV{"value", J.Str{"settings"}}, J.KV{"signalRevision", J.Num{"0"}}])

def activity() -> M.Change:
  M.ActivityLogged{"self", "activity", "warn", "notice", "Visible synthetic warning", 12n}

def assistant() -> M.Change:
  M.MessagePosted{"self", "message", M.Assistant{}, "Visible synthetic assistant", 12n}

def stamp(+cs: List<&2, M.Change>) -> Nat:
  G.SignalRevision.advance(cs, M.State.seq(state()), M.State.seq(M.State.replay(cs, state())))

def kept(+cs: List<&2, M.Change>) -> String:
  yes(Nat.is_eq(stamp(cs), M.State.seq(state())))

def hit(+cs: List<&2, M.Change>) -> String:
  yes(K.SignalCache.hit(K.SignalCache.obtain("epoch", state(), None{}), "epoch", stamp(cs)))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("activity history keeps dependency revision", kept([activity()]), "yes")
    C.Check.str("assistant history keeps dependency revision", kept([assistant()]), "yes")
    C.Check.str("system history keeps dependency revision", kept([M.MessagePosted{"self", "system", M.System{}, "System body", 12n}]), "yes")
    C.Check.str("user input invalidates dependency revision", kept([M.MessagePosted{"self", "user", M.User{}, "New request", 12n}]), "no")
    C.Check.str("approval invalidates", hit([M.AskOpened{"a", "other", "approval", "tool", "Allow", "", 12n}]), "no")
    C.Check.str("question close invalidates", hit([M.AskClosed{"a", "yes", 12n}]), "no")
    C.Check.str("pending invalidates", hit([M.PendingChanged{"other", 1n, 12n}]), "no")
    C.Check.str("work invalidates", hit([M.WorkSet{"other", "watch", "w\twatching", 12n}]), "no")
    C.Check.str("task delegation invalidates", hit([M.TaskDelegated{"task", "self", "other", 1n, "codex", "", 12n}]), "no")
    C.Check.str("task completion invalidates", hit([M.TaskStateSet{"task", M.TaskDone{}, "done", 12n}]), "no")
    C.Check.str("settle invalidates", hit([M.ThreadSettled{"self", False{}, 12n}]), "no")
    C.Check.str("reopen invalidates", hit([M.ThreadWoke{"self", 12n}]), "no")
    C.Check.str("failure invalidates", hit([M.TurnChanged{"other", M.Failed{}, 12n}]), "no")
    C.Check.str("auth hold invalidates", hit([M.SettingSet{"auth.wait.other", "codex", 12n}]), "no")
    C.Check.str("fallback queue invalidates", hit([M.TurnQueued{"self", "fallback:held:1", "held", 12n}]), "no")
    C.Check.str("unclassified event defaults to invalidation", kept([M.ThreadRenamed{"other", "New name", 12n}]), "no")
    C.Check.str("mixed batch cannot hide approval", kept([activity(), M.AskOpened{"a", "self", "input", "tool", "Choose", "", 12n}, assistant()]), "no")
    C.Check.str("empty commit keeps dependency revision", kept(Nil{}), "yes")
