import Base
import ./check.bend as C
import ../src/core/signal.bend as S

# Adversarial cycles with chords, duplicate edges and two separate sources.
# The reference result is every node having both bits. Check queue exhaustion
# as well as values, so a fuel cutoff cannot masquerade as convergence.
def ids(+n: Nat) -> List<&2, String>:
  match n:
    case 0n: Nil{}
    case 1n+k: Nat.show(k) <> ids(k)

def seeds(+n: Nat, m: Map<&2, Nat>) -> Map<&2, Nat>:
  match n:
    case 0n: m
    case 1n+k:
      seeds(k, Map.set(&2, Nat, m, Nat.show(k), Bool.pick(Nat, Nat.is_eq(k, 0n), 1n, Bool.pick(Nat, Nat.is_eq(k, 1n), 2n, 4n))))

def edges(+n: Nat, +size: Nat, m: Map<&2, List<&2, String>>) -> Map<&2, List<&2, String>>:
  match n:
    case 0n: m
    case 1n+k:
      +next = Nat.show(Nat.mod(1n+k, size))
      edges(k, size, Map.set(&2, List<&2, String>, m, Nat.show(k), [next, next, Nat.show(Nat.mod(Nat.add(k, 7n), size)), Nat.show(Nat.mod(Nat.add(k, 13n), size))]))

def both(xs: List<&2, String>, +m: Map<&2, Nat>) -> Bool:
  match xs:
    case Nil{}: True{}
    case id <> rest: Bool.and(Nat.is_eq(S.Signal.at(m, id), 3n), both(rest, m))

def case_of(+size: Nat, reverse: Bool) -> S.SignalStep:
  +order = ids(size)
  S.Signal.drain(Nat.mul(3n, size), S.SignalStep{seeds(size, Map.new(&2, Nat)), Bool.pick(List<&2, String>, reverse, List.reverse(&2, String, order), order)}, edges(size, size, Map.new(&2, List<&2, String>)))

def graph(+size: Nat, +reverse: Bool) -> IO(Unit):
  +result = case_of(size, reverse)
  +name = Nat.show(size) ++ "/" ++ Bool.show(reverse)
  do IO<Unit>:
    C.Check.str("cycle queue converged within 3V " ++ name, Nat.show(S.Signal.pending(result)), "0")
    C.Check.str("cycle result agrees with all-reachable oracle " ++ name, Bool.show(both(ids(size), S.Signal.values(result))), "True")

def main() -> IO(Unit):
  do IO<Unit>:
    graph(2n, False{})
    graph(2n, True{})
    graph(31n, False{})
    graph(31n, True{})
    graph(100n, False{})
    graph(100n, True{})
