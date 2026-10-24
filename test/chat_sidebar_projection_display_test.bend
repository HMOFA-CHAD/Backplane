import Base
import ./check.bend as C
import ./chat_sidebar_projection_test.bend as F
import ../src/core/model.bend as M
import ../src/core/client.bend as U
import ../src/core/signal.bend as SG
import ../src/core/json.bend as J
import ../src/server/thin-actor.bend as A
import ../src/server/thin-view.bend as V
import ../src/server/thin-sidebar-wire.bend as W
import ../src/server/thin-signals.bend as RAW
import ../src/server/thin-side-index.bend as IX
import ../src/server/thin-signal-text.bend as TXT
import ../src/web/sidebar-slot.bend as SLOT

def frame(+u: U.Ui, cached: J.Json) -> J.Json:
  +st = U.Ui.state(u)
  +signals = SG.Signal.index(st)
  V.Render.web.prepared.materialized(V.ActResult{u, Nil{}}, u, J.Json.obj(Nil{}), cached, signals, U.Side.ix(st), TXT.SignalTextCache.values(TXT.SignalTextCache.build("epoch", M.State.seq(st), U.Side.signals.online(u), signals)))

def exact(+before: U.Ui, +after: U.Ui, oldRev: Nat, newRev: Nat) -> String:
  +node = SLOT.Slot.sidebar(J.Json.get_obj(frame(before, J.Null{}), "shown"))
  +cached = A.SidebarImage.lookup([A.SidebarImage{F.image.key(before, "epoch", "view", oldRev), node}], F.image.key(after, "epoch", "view", newRev))
  F.equal(J.Json.show(frame(after, cached)), J.Json.show(frame(after, J.Null{})))

def history(+e: M.Change) -> String:
  exact(F.ordinary(F.state(), 10n), F.ordinary(M.State.apply(F.state(), e), 10n), 1n, 1n)

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("fresh assistant main with retained sidebar exact", history(M.MessagePosted{"self", "a", M.Assistant{}, "Fresh answer 日本語", 10n}), "same")
    C.Check.str("fresh system main with retained sidebar exact", history(M.MessagePosted{"self", "s", M.System{}, "Fresh system", 10n}), "same")
    C.Check.str("fresh tool activity with retained sidebar exact", history(M.ActivityLogged{"self", "a", "warn", "notice", "Fresh warning", 10n}), "same")
    C.Check.str("clock miss keeps whole page exact", exact(F.ordinary(F.state(), 10n), F.ordinary(F.state(), 11n), 1n, 1n), "same")
    C.Check.str("fresh draft and IME miss keep page exact", exact(F.ordinary(F.state(), 10n), U.Ui.scratch_set(F.ordinary(F.state(), 10n), "self", "New 未確定 draft"), 1n, 1n), "same")
    C.Check.str("fresh recipient catalog miss keeps page exact", exact(F.ordinary(F.state(), 10n), U.Ui.info_set(F.ordinary(F.state(), 10n), "models", "Fresh info"), 1n, 1n), "same")
    C.Check.str("online/offline miss keeps page exact", exact(F.ordinary(F.state(), 10n), U.Ui.online(F.ordinary(F.state(), 10n), False{}), 1n, 1n), "same")
    C.Check.str("canonical ask revision miss keeps page exact", exact(F.ordinary(F.state(), 10n), F.ordinary(M.State.apply(F.state(), M.AskOpened{"q", "self", "input", "choose", "Choose", "", 10n}), 10n), 1n, 2n), "same")
    C.Check.str("shelf expansion miss keeps keyboard rows exact", exact(F.ordinary(F.state(), 10n), U.Ui.flag_on(F.ordinary(F.state(), 10n), "active-settled"), 1n, 1n), "same")
    C.Check.str("owned work revision miss keeps Stop exact", exact(F.ordinary(F.state(), 10n), F.ordinary(M.State.apply(F.state(), M.WorkSet{"self", "watch", "w\twatching\t\tbuild\twatch", 10n}), 10n), 1n, 2n), "same")
    C.Check.str("plain metadata save retains one image", F.image.count(A.SideIndex.save(True{}, F.image.seed(), IX.IndexCache.obtain("epoch", F.state(), None{}))), "1")
    C.Check.str("raw signal save retains one image", F.image.count(A.Signals.save(True{}, F.image.seed(), RAW.SignalCache.obtain("epoch", F.state(), None{}))), "1")
    C.Check.str("canonical text save retains one image", F.image.count(A.SignalText.save(True{}, F.image.seed(), TXT.SignalTextCache.build("epoch", 1n, True{}, SG.Signal.index(F.state())))), "1")
    C.Check.str("full picture is wire authority despite private image", W.Region.key([A.SidebarImage{"render-only", J.Null{}}, A.Sidebar{"full-picture", J.Null{}}]), "full-picture")
