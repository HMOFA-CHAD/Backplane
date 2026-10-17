import Base
import ./check.bend as C
import ../src/core/i18n.bend as I
import ../src/core/msgs.bend as MSG
import ../src/core/client.bend as U
import ../src/core/model.bend as M
import ../src/app/layout.bend as L
import ../src/app/nui.bend as N
import ../src/app/bots.bend as BV
import ../src/app/forms.bend as F
import ../src/app/viewer.bend as V
import ../src/gfx/text.bend as X
import ../src/gfx/raster.bend as R
import ../src/gfx/draw.bend as D

# The uncached test face records every drawn code point as a glyph request.
# This exercises the actual layout's texts, without fonts or an X server.
def face.of(f: X.Face) -> X.Face:
  match f:
    case X.Face{_, _, px, asc, desc, lh, miss, name, tab}:
      X.Face{1, True{}, px, asc, desc, lh, miss, name, tab}

def ty(+l: I.Loc) -> L.Ty:
  +f = face.of(X.Text.bitmap())
  L.Ty{Map.new(&2, X.TG), f, f, f, f, f, l}

def ja() -> U.Ui:
  U.Lang.apply(U.Ui.scratch_set(U.Ui.init(100n), "@lang.preview", "1"), "ja", "ja-JP")

def state() -> M.State:
  M.State.replay([M.ProjectCreated{"p", "Board", "/tmp/board", 1n},
    M.ThreadCreated{"t", "p", "A person's title", M.Local{}, "", "", "missing-provider", "", 2n},
    M.MessagePosted{"t", "m", M.User{}, "Leave this message alone", 3n}], M.State.empty())

def ui.of(u: U.Ui) -> U.Ui:
  match u:
    case U.Ui{_, _, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}:
      U.Ui{state(), "t", dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}

def text.ops(os: List<&2, R.Op>, acc: String) -> String:
  match os:
    case Nil{}: acc
    case R.Op{4294967295, _, _, _, cp, 0, _} <> t:
      text.ops(t, SCon{Chr{cp}, acc})
    case _ <> t: text.ops(t, acc)

def text(o: L.Out) -> String:
  match o:
    case L.Out{os, _}: text.ops(os, "")

def hits(o: L.Out) -> List<&2, N.Hit>:
  match o:
    case L.Out{_, hs}: hs

def has(+s: String, v: String) -> String:
  Bool.show(String.contains(s, v))

def captions(hs: List<&2, N.Hit>) -> String:
  match hs:
    case Nil{}: ""
    case N.Hit{_, _, _, _, caption, _} <> t: caption ++ "|" ++ captions(t)

def right.go(hs: List<&2, N.Hit>, +a: String, +v: String) -> U32:
  match hs:
    case Nil{}: 0
    case N.Hit{_, _, x1, _, +action, +value} <> t:
      Bool.pick(U32, Bool.and(String.eq(a, action), String.eq(v, value)), x1, right.go(t, a, v))

def settings() -> L.Out:
  L.Lay.settings(ty(I.Ja{}), state(), N.Nui.init(ui.of(ja()), 1400, 10000), Map.new(&2, String), "test", "", 264, 1400, 10000, 0)

def thread() -> L.Out:
  +font = ty(I.Ja{})
  +n = N.Nui.init(ui.of(ja()), 1400, 900)
  L.Lay.thread(font, L.Lay.memo(font, n, L.TL.memo.none()), n, 264, 1400)

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("settings en", MSG.T.settings.restart(I.En{}), "Continue after a restart")
    C.Check.str("settings ja", MSG.T.settings.restart(I.Ja{}), "再起動後に続行")
    C.Check.str("sidebar en", MSG.T.sidebar.snoozed(I.En{}), "Snoozed")
    C.Check.str("sidebar ja", MSG.T.sidebar.snoozed(I.Ja{}), "スヌーズ中")
    C.Check.str("thread chrome en", MSG.T.thread.subagents(I.En{}), "Subagents")
    C.Check.str("thread chrome ja", MSG.T.thread.subagents(I.Ja{}), "サブエージェント")
    C.Check.str("composer en", MSG.T.composer.placeholder(I.En{}), "Ask anything: @bot, >thread, %project, #room, $skill, /btw")
    C.Check.str("composer ja", MSG.T.composer.placeholder(I.Ja{}), "何でも質問：@bot、>thread、%project、#room、$skill、/btw")
    C.Check.str("menu en", text(L.Lay.button(ty(I.En{}), D.Clip.all(), 0, 0, MSG.T.common.cancel(I.En{}), 0, "cancel", "")), "Cancel")
    C.Check.str("menu ja", text(L.Lay.button(ty(I.Ja{}), D.Clip.all(), 0, 0, MSG.T.common.cancel(I.Ja{}), 0, "cancel", "")), MSG.T.common.cancel(I.Ja{}))
    C.Check.str("approval menu en", captions(L.Ask.choices("approval", "a", "", "")), "Allow|Allow for session|Deny|")
    C.Check.str("approval menu ja", captions(L.Ask.choices.loc(I.Ja{}, "approval", "a", "", "")), MSG.T.approval.allow(I.Ja{}) ++ "|" ++ MSG.T.approval.session(I.Ja{}) ++ "|" ++ MSG.T.approval.deny(I.Ja{}) ++ "|")
    C.Check.str("bots en", BV.Bv.onoff(True{}), "On")
    C.Check.str("bots ja", BV.Bv.onoff.loc(I.Ja{}, True{}), MSG.T.settings.lang.on(I.Ja{}))
    C.Check.str("forms en", text(F.Fm.field(ty(I.En{}), F.Fm.fs(N.Nui.init(U.Ui.init(0n), 800, 600)), D.Clip.all(), 0, 0, 400, "name", "save", "", MSG.T.bots.room.name(I.En{}))), "Room name")
    C.Check.str("forms ja", text(F.Fm.field(ty(I.Ja{}), F.Fm.fs(N.Nui.init(ja(), 800, 600)), D.Clip.all(), 0, 0, 400, "name", "save", "", MSG.T.bots.room.name(I.Ja{}))), MSG.T.bots.room.name(I.Ja{}))
    C.Check.str("viewer en", V.Vx.notice(I.En{}, "No board in this project yet"), "No board in this project yet")
    C.Check.str("viewer ja", V.Vx.notice(I.Ja{}, "No board in this project yet"), MSG.T.viewer.empty.board(I.Ja{}))
    C.Check.str("viewer content retained", V.Vx.notice(I.Ja{}, "a tool's own diagnostic"), "a tool's own diagnostic")
    C.Check.str("viewer error en", V.Vx.notice(I.En{}, "3D export failed: diagnostic"), "3D export failed: diagnostic")
    C.Check.str("viewer error ja", V.Vx.notice(I.Ja{}, "3D export failed: diagnostic"), MSG.T.viewer.export.failed(I.Ja{}, "diagnostic"))
    C.Check.str("picker en default", L.Picker.name(""), "default")
    C.Check.str("picker ja default", L.Picker.name.loc(I.Ja{}, ""), MSG.T.common.default(I.Ja{}))
    C.Check.str("picker model retained", L.Picker.name.loc(I.Ja{}, "claude-opus-5"), "claude-opus-5")
    C.Check.str("pane en", L.Pane.range(3n, 5n, 1234n), " · 4–8 of 1234")
    C.Check.str("pane ja", L.Pane.range.loc(I.Ja{}, 3n, 5n, 1234n), MSG.T.pane.range(I.Ja{}, "4", "8", "1234"))
    C.Check.str("ungrouped count en", MSG.T.settings.settle.days(I.En{}, "1234", "other"), "1234 days")
    C.Check.str("ungrouped count ja", MSG.T.settings.settle.days(I.Ja{}, "1234", "other"), "1234日")
    C.Check.str("voice en", L.Vx.head("live", "mic"), "Listening · mic")
    C.Check.str("voice ja", L.Vx.head.loc(I.Ja{}, "live", "mic"), MSG.T.voice.listening(I.Ja{}, "named", "mic"))
    C.Check.str("provider en", L.Set.cli("", "codex"), "codex is not installed")
    C.Check.str("provider ja", L.Set.cli.loc(I.Ja{}, "", "codex"), MSG.T.settings.provider.missing(I.Ja{}, "codex"))
    C.Check.str("settings draws Japanese", has(text(settings()), MSG.T.settings.voice(I.Ja{})), "True")
    C.Check.str("settings draws thread card", has(text(settings()), MSG.T.settings.settle(I.Ja{})), "True")
    C.Check.str("settings hit retained", Bool.show(U32.is_gt(right.go(hits(settings()), "setting", "restart.continue=off"), 0)), "True")
    C.Check.str("right aligned Japanese chip", U32.show(right.go(hits(L.Set.carry(ty(I.Ja{}), True{}, 300, 700, 100)), "setting", "restart.continue=off")), "984")
    C.Check.str("IPC chips right aligned", U32.show(right.go(hits(L.Set.ipc(ty(I.Ja{}), "on", 300, 700, 100)), "setting", "kicad.ipc=off")), "984")
    C.Check.str("thread title retained", has(text(thread()), "A person's title"), "True")
    C.Check.str("thread draws Japanese composer", has(text(thread()), "何でも質問"), "True")
    C.Check.str("thread retains message", has(text(thread()), "Leave this message alone"), "True")
    C.Check.str("thread header translated", has(text(thread()), MSG.T.thread.viewer(I.Ja{})), "True")
    C.Check.str("thread send hit", Bool.show(U32.is_gt(right.go(hits(thread()), "send", ""), 0)), "True")
