import Base
import ./check.bend as C
import ../src/core/client.bend as U

# The project picker's field is a form field
# ("bfield" "proj"): the browser keeps and merges what is typed, and a
# new query takes the highlight back to the top.

def state(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}: u

def act(+u: U.Ui, +a: String, +v: String) -> U.Ui:
  state(U.Ui.act(u, a, v))

def main() -> IO(Unit):
  do IO<Unit>:
    +p : U.Ui = act(U.Proj.set(U.Ui.init(0n), "old", 3n), "bfield", "proj\u{1f}kicad pro")
    C.Check.str("the project field is a form field", U.Proj.query(p), "kicad pro")
    C.Check.str("and a new query starts at the top", Nat.show(U.Proj.index(p)), "0")
    C.Check.str("another form field leaves the highlight", Nat.show(U.Proj.index(act(U.Proj.set(U.Ui.init(0n), "old", 3n), "bfield", "setq\u{1f}x"))), "3")
