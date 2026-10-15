import Base
import ./check.bend as C
import ../src/core/attach.bend as AT
import ../src/core/client.bend as U
import ../src/app/nui.bend as N
import ../src/app/win.bend as W

def test.n(focus: String) -> N.Nui:
  N.Nui.with_focus(N.Nui.init(U.Ui.select.k(U.Ui.init(17n), "t1"), 800, 600), focus)

def test.commands(s: N.Step) -> String:
  match s:
    case N.Step{_, cs, _}:
      Nat.show(List.length(&2, N.NCmd, cs))

def test.sends(cs: List<&2, N.NCmd>) -> String:
  match cs:
    case Nil{}:
      ""
    case N.NSend{t} <> rest:
      t ++ "\n" ++ test.sends(rest)
    case _ <> rest:
      test.sends(rest)

def test.wire(s: N.Step) -> String:
  match s:
    case N.Step{_, cs, _}:
      test.sends(cs)

def test.parts(+s: String, width: Nat) -> String:
  String.join(AT.Att.paste.parts(s, width), "|")

def test.ev(e: W.WinEv) -> String:
  match e:
    case W.WImage{}:
      "image"
    case _:
      "other"

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("key zero", AT.Att.paste.key(0), "00000000")
    C.Check.str("key hex", AT.Att.paste.key(2309737967), "89abcdef")
    C.Check.str("png name", AT.Att.paste.name("image/png"), "pasted.png")
    C.Check.str("jpeg name", AT.Att.paste.name("image/jpeg"), "pasted.jpg")
    C.Check.str("webp name", AT.Att.paste.name("image/webp"), "pasted.webp")
    C.Check.str("gif name", AT.Att.paste.name("image/gif"), "pasted.gif")
    C.Check.str("bmp name", AT.Att.paste.name("image/bmp"), "pasted.bmp")
    C.Check.str("unknown mime", AT.Att.paste.name("image/x-custom"), "pasted.bin")
    C.Check.str("empty", test.parts("", 4n), "")
    C.Check.str("zero width keeps data", test.parts("QUJD", 0n), "QUJD")
    C.Check.str("exact", test.parts("QUJD", 4n), "QUJD")
    C.Check.str("two exact", test.parts("QUJDREVG", 4n), "QUJD|REVG")
    C.Check.str("remainder", test.parts("QUJDREVGRw==", 8n), "QUJDREVG|Rw==")
    C.Check.str("pieces rejoin", AT.Att.paste.join(AT.Att.paste.parts("QUJDREVGRw==", 4n)), "QUJDREVGRw==")
    C.Check.str("base64 width", Nat.show(AT.Att.paste.width()), "262144")
    C.Check.str("composer upload", test.commands(N.Nui.image.m(False{}, test.n("composer"), "image/png", 3n, "QUJD", "11223344")), "1")
    C.Check.str("attach path upload", test.commands(N.Nui.image.m(False{}, test.n("attach-path"), "image/png", 3n, "QUJD", "11223344")), "1")
    C.Check.str("tour ignores image", test.commands(N.Nui.image.m(True{}, test.n("composer"), "image/png", 3n, "QUJD", "11223344")), "0")
    C.Check.str("terminal ignores image", test.commands(N.Nui.image.m(False{}, test.n("terminal"), "image/png", 3n, "QUJD", "11223344")), "0")
    C.Check.str("project path ignores image", test.commands(N.Nui.image.m(False{}, test.n("project-path"), "image/png", 3n, "QUJD", "11223344")), "0")
    C.Check.str("oversize refuses", test.commands(N.Nui.image.m(False{}, test.n("composer"), "image/png", Nat.add(AT.Att.cap(), 1n), "", "11223344")), "0")
    C.Check.str("image event", test.ev(W.Win.ev(13, 0, 0, 0, 0)), "image")
    C.Check.str("image uses upload RPC", test.wire(N.Nui.image.m(False{}, test.n("composer"), "image/png", 3n, "QUJD", "11223344")),
      "{\"id\":0,\"m\":\"attach.put\",\"p\":{\"thread\":\"t1\",\"key\":\"11223344\",\"name\":\"pasted.png\",\"i\":0,\"last\":true,\"data\":\"QUJD\"}}\n")
    C.Check.str("pieces keep order and final flag", test.wire(N.Nui.image.parts(["QUJD", "REVG"], test.n("composer"), "11223344", "pasted.png", 6n, 0n)),
      "{\"id\":0,\"m\":\"attach.put\",\"p\":{\"thread\":\"t1\",\"key\":\"11223344\",\"name\":\"pasted.png\",\"i\":0,\"last\":false,\"data\":\"QUJD\"}}\n{\"id\":1,\"m\":\"attach.put\",\"p\":{\"thread\":\"t1\",\"key\":\"11223344\",\"name\":\"pasted.png\",\"i\":1,\"last\":true,\"data\":\"REVG\"}}\n")
    C.Check.str("URI drop still attaches", test.commands(N.Nui.drop.m(False{}, test.n("composer"), "file:///tmp/screenshot.png\r\n")), "1")
    C.Check.str("tour ignores URI drop", test.commands(N.Nui.drop.m(True{}, test.n("composer"), "file:///tmp/screenshot.png\r\n")), "0")
