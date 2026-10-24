import Base
import ./check.bend as C
import ./chat_sidebar_projection_test.bend as F
import ../src/core/client.bend as U
import ../src/core/model.bend as M
import ../src/server/thin-actor.bend as A
import ../src/server/thin-sidebar.bend as SC

def exact(+u: U.Ui, +rev: Nat) -> String:
  F.equal(A.SidebarImage.key.shared(False{}, u, "epoch", "view", rev, SC.Sidebar.key(u, "epoch", "view")), A.SidebarImage.key(False{}, u, "epoch", "view", rev))

def same(+u: U.Ui) -> String:
  exact(u, M.State.seq(U.Ui.state(u)))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("equal trusted sequence shares exact key", same(F.ordinary(F.state(), 10n)), "same")
    C.Check.str("history-only difference keeps original metadata key", exact(F.ordinary(M.State.apply(F.state(), M.MessagePosted{"self", "new", M.Assistant{}, "Fresh 日本語 answer", 10n}), 10n), M.State.seq(F.state())), "same")
    C.Check.str("older dependency sequence keeps original fallback", exact(F.ordinary(F.state(), 10n), 1n), "same")
    C.Check.str("zero dependency sequence keeps original fallback", exact(F.ordinary(F.state(), 10n), 0n), "same")
    C.Check.str("future revision cannot share unequal picture", exact(F.ordinary(F.state(), 10n), 999n), "same")
    C.Check.str("Settings still supplies no private image key", A.SidebarImage.key.shared(True{}, F.old.ui(F.state(), 10n), "epoch", "view", 1n, "must-not-use"), "")
    C.Check.str("current draft and IME remain in shared key", same(U.Ui.scratch_set(F.ordinary(F.state(), 10n), "self", "New 未確定 draft")), "same")
    C.Check.str("fresh recipient model info stays in shared key", same(U.Ui.info_set(F.ordinary(F.state(), 10n), "models", "Fresh current models")), "same")
    C.Check.str("exact clock remains in shared key", same(F.ordinary(F.state(), 11n)), "same")
    C.Check.str("offline input remains in shared key", same(U.Ui.online(F.ordinary(F.state(), 10n), False{})), "same")
