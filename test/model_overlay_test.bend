import Base
import ./check.bend as C
import ../src/web/presentation.bend as P
import ../src/web/dom.bend as D
import ../src/core/json.bend as J

def fixture() -> D.Node:
  D.El{"main", "thread", Nil{}, [D.Txt{"canonical history"},
    D.El{"textarea", "composer", [D.At{"id", "composer"}, D.At{"value", "before"}], Nil{}},
    D.El{"div", "model-layer", [D.At{"style", "display:none"}, D.At{"aria-hidden", "true"}],
      [D.El{"button", "", [D.On{"click", "model"}, D.At{"data-value", "server-listed"}], [D.Txt{"server choice"}]}]}]}

def text(open: Bool) -> String:
  J.Json.show(P.Node.write(P.Node.overlay(fixture(), "draft 日本語", open)))

def yes(b: Bool) -> String:
  Bool.pick(String, b, "yes", "no")

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("cached model layer shows immediately", yes(String.contains(text(True{}), "display:contents")), "yes")
    C.Check.str("closed model layer remains hidden", yes(String.contains(text(False{}), "display:none")), "yes")
    C.Check.str("model overlay preserves authoritative history", yes(String.contains(text(True{}), "canonical history")), "yes")
    C.Check.str("model overlay preserves server choice action", yes(String.contains(text(True{}), "server-listed")), "yes")
    C.Check.str("model overlay preserves selected draft", yes(String.contains(text(True{}), "draft 日本語")), "yes")
    C.Check.str("pure model overlay does not mutate input", yes(String.contains(J.Json.show(P.Node.write(fixture())), "display:none")), "yes")
