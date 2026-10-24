import Base
import ./check.bend as C
import ../src/core/client.bend as U

# The model picker stays open after a choice (a model, an effort or a
# provider), so another can follow; only the chip or the shade around it
# ("flag" "models") closes it.

def state(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}: u

def act(+u: U.Ui, +a: String, +v: String) -> U.Ui:
  state(U.Ui.act(u, a, v))

def open() -> U.Ui:
  act(U.Ui.init(0n), "flag", "models")

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("the chip opens the picker", Bool.show(U.Ui.flag(open(), "models")), "True")
    C.Check.str("a model chosen: still open", Bool.show(U.Ui.flag(act(open(), "model", "haiku"), "models")), "True")
    C.Check.str("an effort chosen: still open", Bool.show(U.Ui.flag(act(open(), "effort", "high"), "models")), "True")
    C.Check.str("a provider chosen: still open", Bool.show(U.Ui.flag(act(open(), "effort", "@codex"), "models")), "True")
    C.Check.str("the shade closes it", Bool.show(U.Ui.flag(act(act(open(), "model", "haiku"), "flag", "models"), "models")), "False")
