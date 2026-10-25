import Base
import ../../src/core/model.bend as M
import ../../src/core/client.bend as U
import ../../src/core/i18n.bend as I
import ../../src/core/json.bend as J
import ../../src/core/bot.bend as BT
import ../../src/web/view.bend as V
import ../../src/web/dom.bend as D
import ../../src/web/presentation.bend as P
import ../../src/web/bots.bend as WB
import ../../src/core/botui.bend as BI
import ./workspace-before.bend as B
import ../../src/web/app.bend as A
import ../../src/web/workspace.bend as WS

# Only generated local fixture data. No user events, providers or hardware.
def changes() -> List<&2, M.Change>:
  [M.ProjectCreated{"p", "Navigation fixture", "/tmp/navigation-fixture", 1n},
   M.ThreadCreated{"t", "p", "A long thread title with board layout and enclosure review across several revisions", M.Local{}, "backplane/navigation", "/tmp/navigation-fixture", "codex", "fixture", 2n},
   M.ThreadCreated{"c", "p", "Subagent awaiting review", M.Local{}, "", "", "codex", "", 2n},
   M.ThreadCreated{"fail", "p", "Failed thread remains reachable", M.Local{}, "", "", "codex", "", 2n},
   M.TurnChanged{"t", M.Running{}, 3n}, M.TurnChanged{"fail", M.Failed{}, 3n},
   M.TaskDelegated{"task", "t", "c", 1n, "codex", "", 3n},
   M.AskOpened{"q", "t", "input", "", "Choose a board revision to review.", "", 4n},
   M.AskOpened{"a", "t", "approval", "", "Approve the fixture operation?", "", 4n},
   M.MessagePosted{"t", "m1", M.Assistant{}, "Review the board and enclosure. The current selection belongs to this thread.\n\nA long path: /tmp/navigation-fixture/boards/revision-with-a-long-name/main.kicad_pcb\n\n```text\nexample inner code scrolling is allowed; main navigation must fit\n```", 5n},
   M.MessagePosted{"t", "m2", M.User{}, "Keep this unsent draft while opening the views and menus.", 6n}]

def base() -> U.Ui:
  U.Ui.info_set(U.Ui.info_set(U.Ui.info_set(U.Ui.info_set(
    U.Ui.restore(U.Ui.online(U.Ui.select.k(U.Ui.fold(changes(), U.Ui.init(20n)), "t"), True{}), "t", "Unsent fixture draft"),
    "fab.boards:t", "boards/main/main.kicad_pcb\nboards/main/main.kicad_pcb\nworktrees/sol-placement/main.kicad_pcb\nrevisions/sol-placement/main.kicad_pcb\nbuild/generated/main.kicad_pcb"),
    "fab.board:t", "boards/main/main.kicad_pcb"), "local.mailroom", "on"), "plotnote:fixture", "No model loaded in this navigation fixture")

def ui(bot: Bool, +kind: String) -> U.Ui:
  +u = Bool.pick(U.Ui, bot, U.Ui.fold([M.BotSet{"b", "Fixture bot", "t", 1n, "", 1n}], base()), base())
  A.stamp(U.Side.with_signals(Bool.pick(U.Ui, String.is_empty(kind), u, U.Ui.view_put(u, kind, "/tmp/navigation-fixture/boards/main/main.kicad_pcb"))))

def thread(+before: Bool, +bot: Bool, +u: U.Ui) -> D.Node:
  Bool.pick(D.Node, before, B.Before.thread.h(I.En{}, u, U.Ui.thread(U.Ui.state(u), "t"),
    Bool.pick(List<&2, D.Node>, bot, [WB.WB.head.loc(I.En{}, u, BT.World.bot(M.State.bots(U.Ui.state(u)), "b"), BI.BU.head.bot(u, BT.World.bot(M.State.bots(U.Ui.state(u)), "b"))), WB.WB.tabs(I.En{}, BI.BU.head.bot(u, BT.World.bot(M.State.bots(U.Ui.state(u)), "b")))], Nil{})),
    Bool.pick(D.Node, bot, V.View.bot(I.En{}, u, BT.World.bot(M.State.bots(U.Ui.state(u)), "b")), V.View.thread(I.En{}, u, U.Ui.thread(U.Ui.state(u), "t"))))

def picture(+before: Bool, +bot: Bool, +kind: String) -> D.Node:
  +u = ui(bot, kind)
  D.El{"div", "", [D.At{"class", "app picked" ++ Bool.pick(String, String.is_empty(kind), "", " panel")}],
    D.Dom.cat([V.View.sidebar(I.En{}, u), thread(before, bot, u)], V.View.aside.if(I.En{}, Bool.not(String.is_empty(kind)), kind, u))}

def snapshot(before: Bool, bot: Bool, kind: String) -> String:
  J.Json.show(P.Node.write(picture(before, bot, kind)))

def board_case(+n: Nat) -> String:
  J.Json.show(P.Node.write(D.Dom.div("viewer-bar", V.View.boards.selector(
    Bool.pick(List<&2, String>, Nat.is_eq(n, 0n), Nil{}, Bool.pick(List<&2, String>, Nat.is_eq(n, 1n), ["single.kicad_pcb"],
      ["a/main.kicad_pcb", "a/main.kicad_pcb", "b/main.kicad_pcb"])),
    Bool.pick(String, Nat.is_eq(n, 1n), "/fixture/single.kicad_pcb", "/fixture/b/main.kicad_pcb"), "single.kicad_pcb", "/fixture"))))


def start(bot: Bool, kind: String) -> U.Ui:
  ui(bot, kind)

def step(u: U.Ui, action: String, value: String) -> U.Ui:
  U.Act.ui(A.act(u, action, value))

def frame.node(+before: Bool, +bot: Bool, +u: U.Ui) -> D.Node:
  WS.WS.view(u,
    D.El{"div", "", [D.At{"class", "app picked" ++ Bool.pick(String, U.Ui.panel(u), " panel", "")}],
      D.Dom.cat([V.View.sidebar(I.En{}, u), thread(before, bot, u)], Bool.pick(List<&2, D.Node>, before, B.Before.aside.if(I.En{}, U.Ui.panel(u), U.Ui.view_get(u, "view.kind"), u), V.View.aside.if(I.En{}, U.Ui.panel(u), U.Ui.view_get(u, "view.kind"), u)))},
    V.View.term.loc(I.En{}, U.Ui.term(u, WS.WS.owner(u))))

def frame(before: Bool, bot: Bool, u: U.Ui) -> String:
  J.Json.show(P.Node.write(V.View.one(V.View.expand([frame.node(before, bot, u)]))))

def state(+u: U.Ui) -> String:
  J.Json.show(J.Json.obj([J.KV{"kind", J.Str{U.Ui.view_get(u, "view.kind")}}, J.KV{"path", J.Str{U.Ui.view_get(u, "view.path")}},
    J.KV{"seq", J.Str{Nat.show(U.Ui.seq(u))}}, J.KV{"draft", J.Str{U.Ui.scratch(u, "t")}}, J.KV{"terminalOwner", J.Str{WS.WS.owner(u)}}]))


def stream(u: U.Ui, text: String) -> U.Ui:
  U.Ui.delta(u, "t", text)

def scenario(+u: U.Ui, phase: String) -> U.Ui:
  match phase:
    case "empty": U.Ui.info_set(U.Ui.info_set(U.Ui.info_set(u, "fm.dir:t", "/tmp/navigation-fixture"), "fm.list:t", ""), "mech.root:t", "/tmp/navigation-fixture")
    case "error": U.Ui.info_set(u, "plotnote:" ++ U.Solid.want(u), "Fixture model could not be loaded")
    case "diff": U.Ui.diff(u, J.Json.obj([J.KV{"thread", J.Str{"t"}}, J.KV{"diff", J.Str{""}}]))
    case _: u

def board_identity() -> String:
  J.Json.show(J.Json.obj([
    J.KV{"nested", J.Str{V.View.board.current(["main.kicad_pcb", "nested/main.kicad_pcb"], V.View.board.relative("/fixture/nested/main.kicad_pcb", "/fixture"))}},
    J.KV{"schematic", J.Str{V.View.board.current(["main.kicad_pcb", "nested/main.kicad_pcb"], V.View.board.relative("/fixture/nested/main.kicad_sch", "/fixture"))}},
    J.KV{"unlisted", J.Str{V.View.board.current(["main.kicad_pcb"], V.View.board.relative("/other/main.kicad_pcb", "/fixture"))}}]))

def cat(name: String) -> String:
  A.cat(name)
