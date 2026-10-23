import Base
import ./check.bend as C
import ./sidebar_region_test.bend as F
import ../src/server/thin-actor.bend as A
import ../src/server/thin-view.bend as V
import ../src/server/thin-sidebar.bend as S
import ../src/web/sidebar-slot.bend as SS
import ../src/core/client.bend as U
import ../src/core/json.bend as J
import ../src/core/thin.bend as T
import ../src/core/thin-live.bend as L

def before() -> U.Ui:
  U.Ui.info_set(F.ui(), "models.v", "1")

def action() -> V.ActResult:
  V.Action.run(True{}, U.Ui.info_set(before(), "models.v", "2"), F.request("settings-page", "appearance"), 10n)

def actor() -> A.Actor:
  A.Actor.accept(F.cached(before()), action(), False{})

def cache_hit() -> String:
  +a = actor()
  F.yes(SS.Slot.is(A.Sidebar.lookup(True{}, A.Sidebar.memos(a), F.key(F.prepared(A.Actor.ui(a)))), "aside"))

def full_reply() -> String:
  +p = F.request("settings-page", "appearance")
  +a = actor()
  +got = F.result(A.Actor.render.full(True{}, a, action(), F.state(), T.Index.empty(), p, "epoch", 10n, Nil{}, L.Stream.blank()))
  +want = V.Obj.put(V.Render.acted_live(action(), True{}, F.state(), T.Index.empty(), p, "epoch", 10n, Nil{}, L.Stream.blank()), "mailDraftContext", A.Actor.mail_context(A.Actor.ui(a)))
  F.same(J.Json.show(got), J.Json.show(want))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("identical catalog rehydration counter retains sidebar cache", cache_hit(), "yes")
    C.Check.str("counter-only warm full reply equals uncached fresh reply", full_reply(), "same")
    C.Check.str("actual model content change still invalidates sidebar", F.same(F.key(before()), F.key(U.Ui.info_set(before(), "models", "changed catalog"))), "different")
