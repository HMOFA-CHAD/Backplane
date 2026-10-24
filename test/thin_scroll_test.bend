import Base
import ./check.bend as C
import ../src/server/thin-view.bend as TV
import ../src/core/client.bend as U
import ../src/web/dom.bend as D

# Scrolling up a thread (no "Load earlier" button): the next older page
# starts halfway up the shown one (Page.mid), so the two share 16 rows and
# the view holds still; the timeline's top carries a mark host.js scrolls to.

def ids(+n: Nat, +i: Nat, acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: List.reverse(&2, String, acc)
    case 1n+k: ids(k, Nat.add(i, 1n), Nat.show(Nat.sub(1000n, i)) <> acc)

def marks(ns: List<&2, D.Node>) -> String:
  match ns:
    case Nil{}: ""
    case D.El{+tag, +key, _, _} <> t: tag ++ "#" ++ key ++ " " ++ marks(t)
    case _ <> t: marks(t)

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("a full page: the next starts after its 16th row", TV.Page.mid(ids(32n, 0n, Nil{}), "969"), "985")
    C.Check.str("a short page: after its last", TV.Page.mid(ids(5n, 0n, Nil{}), "996"), "996")
    C.Check.str("more above: a mark, not a button", marks(TV.Render.older(True{}, U.Ui.init(0n))), "div#earlier ")
    C.Check.str("the start: nothing", marks(TV.Render.older(False{}, U.Ui.init(0n))), "")
