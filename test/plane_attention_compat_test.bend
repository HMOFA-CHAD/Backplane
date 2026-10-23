import Base
import ./check.bend as C
import ./signal_ui_test.bend as S
import ../src/core/client.bend as U
import ../src/core/model.bend as M
import ../src/core/plane.bend as P
import ../src/core/i18n.bend as I

law launch_once:
  {P.Plane.need.states(P.Plane.demo.launch(), 200000n) == "l=question,f=failed" : String}
def launch_once():
  {==}

law split_words:
  {P.Plane.counts.of(I.En{}, 3n, 2n, 1n) == "1 need you · 2 failed · 1 running" : String}
def split_words():
  {==}

def bool.word(b: Bool) -> String:
  Bool.pick(String, b, "yes", "no")

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("ordinary tally matches rows", bool.word(P.Plane.tally.same(P.Plane.demo(), 200000n)), "yes")
    C.Check.str("rich tally matches rows", bool.word(P.Plane.tally.same(P.Plane.demo.rich(), 200000n)), "yes")
    C.Check.str("ordinary phone list matches rows", bool.word(P.Plane.list.same(P.Plane.demo(), 200000n)), "yes")
    C.Check.str("rich phone list matches rows", bool.word(P.Plane.list.same(P.Plane.demo.rich(), 200000n)), "yes")
    C.Check.str("delegated child still names parent row", String.join(P.Plane.ids(P.Plane.need(P.Plane.signals.of(S.ui([M.AskOpened{"q", "c", "input", "", "Choose", "", 5n}], True{}), 20n, True{}))), ","), "p")
