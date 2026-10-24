import Base
import ./check.bend as C
import ../src/core/json.bend as J
import ../src/core/client.bend as U
import ../src/core/model.bend as M
import ../src/web/app.bend as A

# A thread picked while Settings is open leaves Settings, on every path:
# the shared action, the web's hub-drawn session and its local Ui.

def base() -> U.Ui:
  U.Ui.select.k(U.Ui.fold([M.ProjectCreated{"p", "Project", "/fixture", 1n},
    M.ThreadCreated{"current", "p", "Current thread", M.Local{}, "", "/fixture", "codex", "", 1n},
    M.ThreadCreated{"other", "p", "Other thread", M.Local{}, "", "/fixture", "codex", "", 1n},
    M.MessagePosted{"current", "latest", M.Assistant{}, "hello", 2n}], U.Ui.init(2n)), "current")

# Settings open over "current", with drafts in both threads and another flag on
def opened() -> U.Ui:
  U.Ui.flag_on(U.Ui.flag_on(U.Ui.scratch_set(U.Ui.scratch_set(base(), "current", "DRAFT_CURRENT"), "other", "DRAFT_OTHER"), "old-projects"), "settings")

def t_act(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}: u

def t_picked(id: String) -> J.Json:
  A.presentation_choice("select", A.presentation(opened()), id)

def t_flag(s: J.Json, k: String) -> String:
  Bool.show(J.Json.get_bool(J.Json.get_obj(s, "open"), k, False{}))

def t_draft(s: J.Json, k: String) -> String:
  J.Json.get_str(J.Json.get_obj(s, "drafts"), k, "")

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("fixture has Settings open", Bool.show(U.Ui.flag(opened(), "settings")), "True")
    C.Check.str("action: another thread leaves Settings", Bool.show(U.Ui.flag(t_act(U.Ui.act(opened(), "select", "other")), "settings")), "False")
    C.Check.str("action: another thread is shown", U.Ui.sel(t_act(U.Ui.act(opened(), "select", "other"))), "other")
    C.Check.str("action: the same thread leaves Settings", Bool.show(U.Ui.flag(t_act(U.Ui.act(opened(), "select", "current")), "settings")), "False")
    C.Check.str("action: the same thread stays shown", U.Ui.sel(t_act(U.Ui.act(opened(), "select", "current")), "current")
    C.Check.str("action: drafts kept", U.Ui.scratch(t_act(U.Ui.act(opened(), "select", "other")), "current"), "DRAFT_CURRENT")
    C.Check.str("session: Settings open before", t_flag(A.presentation(opened()), "settings"), "True")
    C.Check.str("session: another thread leaves Settings", t_flag(t_picked("other"), "settings"), "False")
    C.Check.str("session: another thread is shown", J.Json.get_str(t_picked("other"), "sel", ""), "other")
    C.Check.str("session: the same thread leaves Settings", t_flag(t_picked("current"), "settings"), "False")
    C.Check.str("session: the same thread stays shown", J.Json.get_str(t_picked("current"), "sel", ""), "current")
    C.Check.str("session: the left thread's draft kept", t_draft(t_picked("other"), "current"), "DRAFT_CURRENT")
    C.Check.str("session: the chosen thread's draft kept", t_draft(t_picked("other"), "other"), "DRAFT_OTHER")
    C.Check.str("session: same thread keeps its draft", t_draft(t_picked("current"), "current"), "DRAFT_CURRENT")
    C.Check.str("session: other flags untouched", t_flag(t_picked("other"), "old-projects"), "True")
    C.Check.str("local Ui: same thread leaves Settings", Bool.show(U.Ui.flag(A.presentation_select(opened(), "current"), "settings")), "False")
    C.Check.str("local Ui: draft kept", U.Ui.scratch(A.presentation_select(opened(), "current"), "current"), "DRAFT_CURRENT")
    C.Check.str("draft edit in Settings keeps Settings", t_flag(A.presentation_choice("draft", A.presentation(opened()), "typed"), "settings"), "True")
