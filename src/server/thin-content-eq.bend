import Base
import ../core/json.bend as J
import ../core/eq.bend as Q

# Exact structural comparison of actual rendered JSON, not a dependency key.
# ContentEq.same is the server-native boundary; go remains the pure oracle.
def ContentEq.go(a: J.Json, b: J.Json) -> Bool:
  match a b:
    case J.Null{} J.Null{}: True{}
    case J.Flag{x} J.Flag{y}: Q.Eq.bool(x, y)
    case J.Num{x} J.Num{y}: Q.Eq.str(x, y)
    case J.Str{x} J.Str{y}: Q.Eq.str(x, y)
    case J.Arr{x} J.Arr{y}: ContentEq.go(x, y)
    case J.Obj{x} J.Obj{y}: ContentEq.go(x, y)
    case J.Item{x, xt} J.Item{y, yt}: Bool.and(ContentEq.go(x, y), ContentEq.go(xt, yt))
    case J.Field{k, x, xt} J.Field{l, y, yt}: Bool.and(Q.Eq.str(k, l), Bool.and(ContentEq.go(x, y), ContentEq.go(xt, yt)))
    case J.End{} J.End{}: True{}
    case _ _: False{}

def ContentEq.same(a: J.Json, b: J.Json) -> Bool:
  ContentEq.go(a, b)
