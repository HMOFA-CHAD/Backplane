import Base
import ./check.bend as C
import ./plane_attention_test.bend as A

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("count and chat are separate keyboard buttons", A.uber("2 failed"), "button uber b1,button uber-bot b1|status")
    C.Check.str("empty count has no empty keyboard target", A.uber(""), "button uber b1")
