import Base
import ./check.bend as C
import ./sidebar_index_display_test.bend as F
import ../src/core/model.bend as M
import ../src/core/client.bend as U

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("activity main and metadata-only sidebar exactly match original", F.changed(M.ActivityLogged{"self", "a", "warn", "notice", "Fresh warning", 10n}), "yes")
    C.Check.str("assistant main and metadata-only sidebar exactly match original", F.changed(M.MessagePosted{"self", "a", M.Assistant{}, "Fresh answer", 10n}), "yes")
    C.Check.str("system main and metadata-only sidebar exactly match original", F.changed(M.MessagePosted{"self", "a", M.System{}, "Fresh system", 10n}), "yes")
    C.Check.str("history with reserved-info fallback exactly matches", F.equal(U.Ui.info_set(F.ui(M.State.apply(F.state(), M.ActivityLogged{"self", "a", "warn", "notice", "Fresh", 10n}), 10n), "@signal:ghost", "3"), False{}), "yes")
    C.Check.str("project metadata remains available to sidebar", F.changed(M.ProjectCreated{"q", "New", "/tmp/new", 10n}), "yes")
    C.Check.str("queued input remains available to sidebar", F.changed(M.TurnQueued{"self", "q", "Pending", 10n}), "yes")
