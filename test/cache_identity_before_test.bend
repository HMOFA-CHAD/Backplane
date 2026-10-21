import Base
import ./check.bend as C
import ../src/core/auth.bend as A

def main() -> IO(Unit):
  C.Check.str("old successful pairing header has no readable cache identity", Bool.show(String.contains(A.Auth.cookie("secret", True{}), "bp_cache_v1=")), "True")
