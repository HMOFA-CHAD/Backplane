import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/client.bend as U
import ../src/core/signal.bend as G
import ../src/core/json.bend as J
import ../src/server/thin-sidebar.bend as S

def state() -> M.State:
  M.State.replay([M.ProjectCreated{"p", "Board", "/tmp/sidebar-read", 1n},
    M.ThreadCreated{"self", "p", "Here", M.Local{}, "", "", "codex", "", 2n}], M.State.empty())

def ui(st: M.State, clock: Nat) -> U.Ui:
  U.Ui.info_set(U.Ui.scratch_set(U.Ui.flag_on(U.Ui.select.k(U.Ui.adopt.raw(U.Ui.init(clock), st), "self"), "settings"), "self", "PRIVATE 日本語 IME draft"), "local.mailroom", "on")

def key(u: U.Ui) -> String:
  S.Sidebar.key.revision(u, "epoch", "view", M.State.seq(state()))

def same(a: String, b: String) -> String:
  Bool.pick(String, C.Check.same(a, b), "same", "different")

def event(+e: M.Change) -> String:
  +st = M.State.apply(state(), e)
  same(key(ui(state(), 10n)), S.Sidebar.key.revision(ui(st, 10n), "epoch", "view", G.SignalRevision.advance([e], M.State.seq(state()), M.State.seq(st))))

def Jreq() -> J.Json:
  J.Json.obj([J.KV{"action", J.Str{"term-key"}}, J.KV{"value", J.Str{"x"}}])

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("same clock activity retains sidebar key", event(M.ActivityLogged{"self", "a", "warn", "notice", "Fresh warning", 10n}), "same")
    C.Check.str("same clock assistant retains sidebar key", event(M.MessagePosted{"self", "a", M.Assistant{}, "Fresh answer", 10n}), "same")
    C.Check.str("same clock system retains sidebar key", event(M.MessagePosted{"self", "a", M.System{}, "Fresh system", 10n}), "same")
    C.Check.str("user input invalidates sidebar", event(M.MessagePosted{"self", "a", M.User{}, "Fresh request", 10n}), "different")
    C.Check.str("approval invalidates sidebar", event(M.AskOpened{"a", "self", "approval", "tool", "Allow", "", 10n}), "different")
    C.Check.str("queued request invalidates sidebar", event(M.TurnQueued{"self", "m", "Work", 10n}), "different")
    C.Check.str("watch work invalidates sidebar", event(M.WorkSet{"self", "watch", "w\twatching", 10n}), "different")
    C.Check.str("project metadata invalidates sidebar", event(M.ProjectCreated{"q", "New", "/tmp/q", 10n}), "different")
    C.Check.str("navigation invalidates sidebar", event(M.SettingSet{"thread.parent.self", "other", 10n}), "different")
    C.Check.str("exact clock still invalidates", same(key(ui(state(), 10n)), key(ui(state(), 11n))), "different")
    C.Check.str("draft still invalidates", same(key(ui(state(), 10n)), key(U.Ui.scratch_set(ui(state(), 10n), "self", "changed draft"))), "different")
    C.Check.str("info still invalidates", same(key(ui(state(), 10n)), key(U.Ui.info_set(ui(state(), 10n), "status", "fresh"))), "different")
    C.Check.str("online still invalidates", same(key(U.Ui.online(ui(state(), 10n), True{})), key(U.Ui.online(ui(state(), 10n), False{}))), "different")
    C.Check.str("fold still invalidates", same(key(ui(state(), 10n)), key(U.Ui.flag_on(ui(state(), 10n), "conversation-history"))), "different")
    C.Check.str("search still invalidates", same(key(ui(state(), 10n)), key(U.Ui.scratch_set(ui(state(), 10n), "@f.pq", "query"))), "different")
    C.Check.str("epoch still invalidates", same(key(ui(state(), 10n)), S.Sidebar.key.revision(ui(state(), 10n), "other-epoch", "view", M.State.seq(state()))), "different")
    C.Check.str("view still invalidates", same(key(ui(state(), 10n)), S.Sidebar.key.revision(ui(state(), 10n), "epoch", "other-view", M.State.seq(state()))), "different")
    C.Check.str("selection still invalidates", same(key(ui(state(), 10n)), key(U.Ui.select.k(ui(state(), 10n), "other"))), "different")
    C.Check.str("legacy key still uses full canonical sequence", same(S.Sidebar.key(ui(state(), 10n), "epoch", "view"), S.Sidebar.key(ui(M.State.apply(state(), M.ActivityLogged{"self", "a", "warn", "notice", "Fresh", 10n}), 10n), "epoch", "view")), "different")
    C.Check.str("non Settings actions still refuse reuse", Bool.pick(String, S.Sidebar.request(Jreq(), ui(state(), 10n)), "yes", "no"), "no")
