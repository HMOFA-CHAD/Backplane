import Base
import ./check.bend as C
import ../src/web/presentation.bend as P
import ../src/web/dom.bend as D
import ../src/core/json.bend as J
import ../src/core/client.bend as U
import ../src/core/model.bend as M
import ../src/web/app.bend as A
import ../src/web/session.bend as S
import ../src/web/bots.bend as WB
import ../src/core/i18n.bend as I

def fixture() -> D.Node:
  D.El{"div", "thread:one", [D.At{"class", "thread"}, D.On{"click", "select"}, D.At{"data-value", "one"}],
    [D.Txt{"日本語 👋 é <script>literal text</script>"}, D.El{"input", "composer", [D.At{"id", "composer"}, D.At{"value", "draft\nsecond line"}, D.On{"input", "draft"}], Nil{}},
      D.El{"svg", "icon", [D.At{"viewBox", "0 0 24 24"}], [D.El{"path", "", [D.At{"d", "M0 0L1 1"}], Nil{}}]}]}

def roundtrip(node: D.Node) -> String:
  J.Json.show(P.Node.write(P.Node.read(P.Node.write(node))))

def current() -> U.Ui:
  U.Ui.select.k(U.Ui.fold([M.ProjectCreated{"p", "Project", "/fixture", 1n},
    M.ThreadCreated{"current", "p", "Current thread", M.Local{}, "", "/fixture", "codex", "", 1n},
    M.MessagePosted{"current", "latest", M.Assistant{}, "LATEST_VISIBLE_CURRENT_日本語", 2n}], U.Ui.init(2n)), "current")

def yes(value: Bool) -> String:
  Bool.pick(String, value, "yes", "no")

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("normal tree preserves keys attributes actions order and Unicode text", roundtrip(fixture()), J.Json.show(P.Node.write(fixture())))
    C.Check.str("plain text remains text", roundtrip(D.Txt{"<img src=x onerror=alert(1)>"}), J.Json.show(P.Node.write(D.Txt{"<img src=x onerror=alert(1)>"})))
    C.Check.str("unknown wire node is empty text", J.Json.show(P.Node.write(P.Node.read(J.Json.obj([J.KV{"type", J.Str{"unknown"}}])))), J.Json.show(P.Node.write(D.Txt{""})))
    C.Check.str("empty keyed element remains exact", roundtrip(D.El{"div", "empty", Nil{}, Nil{}}), J.Json.show(P.Node.write(D.El{"div", "empty", Nil{}, Nil{}})))
    C.Check.str("actual normal current view survives renderer transport", J.Json.show(A.presentation_view(current())), J.Json.show(P.Node.write(A.presentation_node(A.presentation_view(current())))))
    C.Check.str("early view contains actual current message", yes(String.contains(J.Json.show(A.presentation_view(current())), "LATEST_VISIBLE_CURRENT_日本語")), "yes")
    C.Check.str("view result does not change canonical cursor", A.seq(A.presentation_handoff(current(), A.presentation(current()))), A.seq(current()))
    C.Check.str("shared result carries normal web renderer", Nat.show(J.Json.get_nat(S.WebSession.result(current(), J.Json.arr(Nil{}), 3n), "web", 0n)), "1")
    C.Check.str("provisional Mailroom send refuses now without queued commands", Nat.show(List.length(&2, U.Cmd, U.Act.cmds(S.WebSession.act(current(), "mail-send", "")))), "0")
    C.Check.str("provisional Browser navigation refuses now", Nat.show(List.length(&2, U.Cmd, U.Act.cmds(S.WebSession.act(current(), "br-go", "https://example.invalid")))), "0")
    C.Check.str("provisional Teach refuses now", Nat.show(List.length(&2, U.Cmd, U.Act.cmds(S.WebSession.act(current(), "tk-teach", "owner")))), "0")
    C.Check.str("current conversation draft remains available", yes(S.WebSession.allowed("draft")), "yes")
    C.Check.str("provisional Browser emits no direct guest surface", yes(String.contains(J.Json.show(P.Node.write(WB.WB.browser.surface.loc(I.En{}, U.Ui.scratch_set(U.Ui.scratch_set(current(), "@desktop.browser", "1"), "@presentation", "1"), "current", "Current"))), "data-desktop-browser-owner")), "no")
    C.Check.str("canonical Browser still emits its ordinary direct surface", yes(String.contains(J.Json.show(P.Node.write(WB.WB.browser.surface.loc(I.En{}, U.Ui.scratch_set(current(), "@desktop.browser", "1"), "current", "Current"))), "data-desktop-browser-owner")), "yes")
    C.Check.str("provisional Mailroom emits no reader or body cache", yes(String.contains(J.Json.show(P.Node.write(WB.WB.mail.presentation(True{}, I.En{}, current()))), "mail-messages")), "no")
    C.Check.str("canonical Mailroom retains its normal toolbar", yes(String.contains(J.Json.show(P.Node.write(WB.WB.mail.presentation(False{}, I.En{}, current()))), "mail-toolbar")), "yes")
    C.Check.str("canonical handoff removes only presentation marker", U.Ui.scratch(A.presentation_handoff(current(), A.presentation(U.Ui.scratch_set(current(), "@presentation", "1"))), "@presentation"), "")
    C.Check.str("corrupt cache reset owns an actual fresh cursor", A.seq(A.presentation_reset(current(), 3n, "cid")), "0")
    C.Check.str("corrupt cache reset owns an actual empty origin", A.origin(A.presentation_reset(U.Ui.info_set(current(), "origin", "cached-origin"), 3n, "cid")), "")
    C.Check.str("cache reset retains the new ordinary composer draft", U.Ui.scratch(A.presentation_reset(U.Ui.scratch_set(current(), "current", "new 日本語 draft"), 3n, "cid"), "current"), "new 日本語 draft")
    C.Check.str("newer draft overlays the normal composer field", yes(String.contains(J.Json.show(P.Node.write(P.Node.draft(fixture(), "NEW_DRAFT_日本語"))), "NEW_DRAFT_日本語")), "yes")
    C.Check.str("draft overlay preserves conversation text", yes(String.contains(J.Json.show(P.Node.write(P.Node.draft(fixture(), "NEW_DRAFT_日本語"))), "literal text")), "yes")
    C.Check.str("draft overlay removes the obsolete field value", yes(String.contains(J.Json.show(P.Node.write(P.Node.draft(fixture(), "NEW_DRAFT_日本語"))), "second line")), "no")
