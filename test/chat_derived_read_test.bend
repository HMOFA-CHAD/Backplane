import Base
import ./check.bend as C
import ../src/core/client.bend as U
import ../src/core/model.bend as M
import ../src/core/json.bend as J
import ../src/core/signal.bend as SG
import ../src/server/thin-sidebar.bend as X
import ../src/server/thin-side-index.bend as IX
import ../src/server/thin-signal-text.bend as TXT
import ../src/web/app.bend as A
import ../src/web/presentation.bend as WP

def state() -> M.State:
  M.State.replay([M.ProjectCreated{"p", "Board", "/tmp/chat-derived", 1n}, M.ThreadCreated{"self", "p", "Here", M.Local{}, "", "", "codex", "", 2n}, M.ThreadCreated{"other", "p", "Other", M.Local{}, "", "", "codex", "", 3n}], M.State.empty())

def ui(st: M.State) -> U.Ui:
  U.Ui.info_set(U.Ui.scratch_set(U.Ui.select.k(U.Ui.adopt.raw(U.Ui.init(11n), st), "self"), "self", "PRIVATE 日本語 IME draft"), "local.mailroom", "on")

def request(action: String, value: String) -> J.Json:
  J.Json.obj([J.KV{"action", J.Str{action}}, J.KV{"value", J.Str{value}}])

def yes(b: Bool) -> String:
  Bool.pick(String, b, "yes", "no")

def same(a: String, b: String) -> String:
  yes(C.Check.same(a, b))

def derived(action: String, value: String) -> String:
  yes(X.Sidebar.derived(request(action, value), ui(state())))

def key(+settings: Bool, +u: U.Ui, revision: Nat) -> String:
  X.Sidebar.key.for(settings, u, "epoch", "view", revision)

def exact(+u: U.Ui) -> String:
  +st = U.Ui.state(u)
  +ix = IX.IndexCache.index(IX.IndexCache.obtain("epoch", st, None{}))
  same(J.Json.show(WP.Node.write(A.view_sidebar_materialized(u, False{}, ix, SG.Signal.index(st), TXT.SignalTextCache.values(TXT.SignalTextCache.build("epoch", M.State.seq(st), U.Side.signals.online(u), SG.Signal.index(st)))))), J.Json.show(WP.Node.write(A.view_sidebar(u, False{}))))

def changed(e: M.Change) -> String:
  exact(U.Ui.online(ui(M.State.apply(state(), e)), True{}))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("ordinary chat read uses derived data", derived("", ""), "yes")
    C.Check.str("ordinary chat never gets Settings picture lookup", yes(X.Sidebar.request(request("", ""), ui(state()))), "no")
    C.Check.str("Settings open retains qualified path", derived("flag", "settings"), "yes")
    C.Check.str("Settings categories retain qualified path", derived("settings-page", "appearance"), "yes")
    C.Check.str("send action retains original nonread path", derived("send", ""), "no")
    C.Check.str("other actions retain original nonread path", derived("view-kind", "board"), "no")
    C.Check.str("chat key is original full-sequence key", same(key(False{}, ui(state()), 0n), X.Sidebar.key(ui(state()), "epoch", "view")), "yes")
    C.Check.str("chat key ignores supplied metadata revision", same(key(False{}, ui(state()), 0n), key(False{}, ui(state()), 999n)), "yes")
    C.Check.str("fresh history changes chat picture key", same(key(False{}, ui(state()), 0n), key(False{}, ui(M.State.apply(state(), M.MessagePosted{"self", "a", M.Assistant{}, "Fresh", 4n})), 0n)), "no")
    C.Check.str("Settings key remains qualified metadata key", same(key(True{}, ui(state()), 9n), X.Sidebar.key.revision(ui(state()), "epoch", "view", 9n)), "yes")
    C.Check.str("whole ordinary conversation page exact", exact(U.Ui.online(ui(state()), True{})), "yes")
    C.Check.str("fresh assistant timeline exact", changed(M.MessagePosted{"self", "a", M.Assistant{}, "Fresh reply 日本語", 4n}), "yes")
    C.Check.str("canonical question and ask actions exact", changed(M.AskOpened{"q", "self", "input", "choose", "Choose input", "", 4n}), "yes")
    C.Check.str("owned work and Stop state exact", changed(M.WorkSet{"self", "watch", "w\twatching\t\tbuild\twatch", 4n}), "yes")
    C.Check.str("user request and shelf freshness exact", changed(M.MessagePosted{"self", "u", M.User{}, "New user request", 4n}), "yes")
    C.Check.str("offline conversation state exact", exact(U.Ui.online(ui(state()), False{})), "yes")
