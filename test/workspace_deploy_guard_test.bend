import Base
import ./check.bend as C
import ../src/web/view.bend as V
import ../src/web/dom.bend as D
import ../src/core/i18n.bend as I

def shaded(xs: List<&2, D.Attr>) -> Bool:
  match xs:
    case Nil{}: False{}
    case D.At{"class", value} <> tail: Bool.or(String.eq(value, "shade"), shaded(tail))
    case _ <> tail: shaded(tail)

def backdrops(xs: List<&2, D.Node>) -> Nat:
  match xs:
    case Nil{}: 0n
    case D.El{_, _, attrs, kids} <> tail:
      Nat.add(Bool.pick(Nat, shaded(attrs), 1n, 0n), Nat.add(backdrops(kids), backdrops(tail)))
    case _ <> tail: backdrops(tail)

def menu(open: Bool) -> List<&2, D.Node>:
  V.View.menu.loc(I.En{}, open, ["fixture"], "fixture", "{}", "codex", Nil{}, "", "", False{})

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("closed model menu has no modal backdrop", Nat.show(backdrops(menu(False{}))), "0")
    C.Check.str("open model menu keeps modal backdrop", Nat.show(backdrops(menu(True{}))), "1")
