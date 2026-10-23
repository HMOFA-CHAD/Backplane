import Base
import ./check.bend as C
import ./plane_attention_test.bend as A
import ../src/core/model.bend as M

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("sidebar tally agrees", A.tally(A.failed()), A.counts(A.failed()))
    C.Check.str("tally with an ask agrees", A.tally(List.append(&2, M.Change, A.failed(), [M.AskOpened{"q1", "int", "approval", "Bash", "git push", "", 16n}])), A.counts(List.append(&2, M.Change, A.failed(), [M.AskOpened{"q1", "int", "approval", "Bash", "git push", "", 16n}])))
