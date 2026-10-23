import Base
import ./check.bend as C
import ./opencode_test.bend as T
import ../src/core/acp.bend as A
import ../src/core/opencode.bend as O

# Continue only the failed fixture assertion; the other37 cases are retained.
def main() -> IO(Unit):
  C.Check.str("oc resumed prompt", T.method(T.sends(O.Ocp.line(A.Acp.new(), T.turn("S0"), "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"configOptions\":[]}}"))), "session/prompt")
