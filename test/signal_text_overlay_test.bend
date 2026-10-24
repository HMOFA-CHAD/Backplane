import Base
import ./check.bend as C
import ../src/core/signal.bend as G
import ../src/core/json.bend as J

def fields(xs: List<&2, Sigma<&2, &2, String, _ => String>>) -> List<&2, J.KV>:
  match xs:
    case Nil{}: Nil{}
    case (k, v) <> rest: J.KV{k, J.Str{v}} <> fields(rest)

def show(m: Map<&2, String>) -> String:
  J.Json.show(J.Json.obj(fields(Map.to_list(&2, String, m))))

def signals() -> Map<&2, Nat>:
  Map.set(&2, Nat, Map.set(&2, Nat, Map.new(&2, Nat), "working", 1n), "ask", 3n)

def exact(+online: Bool, +info: Map<&2, String>) -> String:
  Bool.pick(String, C.Check.same(show(G.Signal.cache(online, signals(), info)), show(G.Signal.cache.overlay(G.Signal.cache(online, signals(), Map.new(&2, String)), info))), "same", "different")

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("complete empty-info online cache exactly matches", exact(True{}, Map.new(&2, String)), "same")
    C.Check.str("complete empty-info offline cache exactly matches", exact(False{}, Map.new(&2, String)), "same")
    C.Check.str("complete known/unknown reserved and recipient maps exactly match", exact(True{}, Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.new(&2, String), "@signal:working", "999"), "@signal:ghost", "3"), "models", "fresh catalog")), "same")
    C.Check.str("complete offline flag collision exactly matches", exact(False{}, Map.set(&2, String, MLeaf{"@signal.online", "1"}, "status", "fresh")), "same")
