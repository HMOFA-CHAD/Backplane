import Base
import ./ride_receipts_render.bend as R
import ./thin_chat_receipts_test.bend as F
import ./orphan_chat_stamps_test.bend as O
import ../src/core/model.bend as M
import ../src/core/client.bend as U
import ../src/core/json.bend as J
import ../src/web/app.bend as A
import ../src/web/view.bend as V
import ../src/web/dom.bend as D
import ../src/web/presentation.bend as P

# Authored production snapshots, UNRUN. Expand memo bodies so stamp-only
# wrappers cannot pass by hiding behind a bp-memo shell. The sole controller
# uses the actual artifact CSS/host for geometry and incremental acceptance.
def snapshot(u: U.Ui) -> J.Json:
  P.Node.write(D.Dom.div("snapshot", V.View.expand([A.view(u)])))

def empty.rows() -> List<&2, M.Change>:
  [M.MessagePosted{"bub-chat", "empty-1222", M.Assistant{}, "", 1792772568n},
   M.MessagePosted{"bub-chat", "empty-1223", M.Assistant{}, "", 1792772585n},
   M.MessagePosted{"bub-chat", "empty-1227", M.Assistant{}, "", 1792772876n},
   M.MessagePosted{"bub-chat", "empty-1232", M.Assistant{}, "", 1792773154n}]

def screenshot(noisy: Bool) -> U.Ui:
  +es = List.append(&2, M.Change, F.metadata(),
    M.MessagePosted{"bub-chat", "real-before", M.Assistant{}, "Real preceding assistant message.", 1792772545n} <>
    List.append(&2, M.Change, Bool.pick(List<&2, M.Change>, noisy, empty.rows(), Nil{}),
      [M.MessagePosted{"bub-chat", "real-after", M.Assistant{}, "Real following assistant message.", 1792773210n}]))
  U.Act.ui(U.Uber.show(U.Ui.info_set(U.Ui.online(U.Ui.fold(es, U.Ui.init(1792773600n)), True{}), "local.mailroom", "on")))

def saturated() -> U.Ui:
  U.Ui.fold(O.empty.posts(96n, Nil{}), R.bot())

def new_empty_turn() -> U.Ui:
  U.Ui.fold([M.TurnChanged{"bub-chat", M.Running{}, 300n},
    M.ActivityLogged{"bub-chat", "ride:empty-turn", "info", "ride", "internal receipt", 301n},
    M.MessagePosted{"bub-chat", "new-empty-final", M.Assistant{}, " \t\n", 302n},
    M.TurnChanged{"bub-chat", M.Completed{}, 303n}], R.bot())

def first_delta() -> U.Ui:
  U.Ui.recv(U.Ui.fold([M.TurnChanged{"bub-chat", M.Running{}, 304n}], new_empty_turn()),
    R.parsed("{\"t\":\"delta\",\"thread\":\"bub-chat\",\"text\":\"First visible streaming delta after empty turn.\"}"))

def new_receipt() -> U.Ui:
  U.Ui.fold([M.ActivityLogged{"bub-chat", "ride:after-empty-stream", "info", "ride", "internal receipt", 305n}], first_delta())

def notice() -> U.Ui:
  U.Ui.fold([M.ActivityLogged{"bub-chat", "context-session", "info", "session", "Meaningful OpenCode context reset.", 306n},
    M.ActivityLogged{"bub-chat", "ride:warning-stays", "warn", "ride", "Meaningful warning stays.", 307n}], new_receipt())

# Integrator-only old-wrapper reference: retain the real App shell while
# substituting View.entries.shown BEFORE the new chat projection. This is
# the exact former message wrapper path, never a hand-written blank div.
def legacy.children(xs: List<&2, D.Node>, +entries: List<&2, D.Node>) -> List<&2, D.Node>:
  match xs:
    case Nil{}: Nil{}
    case D.Txt{t} <> rest: D.Txt{t} <> legacy.children(rest, entries)
    case D.El{tag, key, +attrs, kids} <> rest:
      D.El{tag, key, attrs, Bool.pick(List<&2, D.Node>, String.eq(V.View.attr(attrs, "id"), "timeline"), entries, legacy.children(kids, entries))} <> legacy.children(rest, entries)

def legacy.screenshot() -> J.Json:
  +u = screenshot(True{})
  +entries : List<&2, M.Entry> = O.before() <> List.append(&2, M.Entry, O.screenshot.empty(), [O.after()])
  P.Node.write(D.Dom.div("snapshot", V.View.expand(legacy.children([A.view(u)], V.View.entries.shown(U.Lang.loc(u), entries, U.Ui.state(u), "bub-chat", U.Ui.infos(u), False{}, U.Ec.none())))))

def main() -> IO(Unit):
  IO.print(J.Json.show(J.Json.obj([
    J.KV{"screenshotBaseline", snapshot(screenshot(False{}))},
    J.KV{"legacyScreenshotWrappers", legacy.screenshot()},
    J.KV{"screenshotLoaded", snapshot(screenshot(True{}))},
    J.KV{"baselineControls", snapshot(R.bot())},
    J.KV{"saturatedEmptyAndReceipts", snapshot(saturated())},
    J.KV{"newEmptyTurn", snapshot(new_empty_turn())},
    J.KV{"firstDelta", snapshot(first_delta())},
    J.KV{"newReceiptDuringStream", snapshot(new_receipt())},
    J.KV{"newSessionAndWarning", snapshot(notice())}])) ++ "\n")
