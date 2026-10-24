import Base
import ./check.bend as C
import ../src/core/client.bend as U
import ../src/core/signal.bend as SIGREV
import ../src/server/thin-signals.bend as SGV

# Canonical-derived bits may be supplied without changing UI decoration.
law side_signals_given_eq:
  for +u: U.Ui
  {U.Side.with_signals.given(u, SIGREV.Signal.index(U.Ui.state(u))) == U.Side.with_signals(u) : U.Ui}

law signal_cache_epoch_miss:
  for +n: Nat
  for m: Map<&2, Nat>
  {SGV.SignalCache.hit(SGV.SignalCache{"old", n, m, True{}}, "new", n) == False{} : Bool}

def side_signals_given_eq(u):
  match u:
    case U.Ui{st, se, dr, li, op, on, now, ad, pa, ve, ri, wa, er, no, nf, ob, tr}: {==}

def signal_cache_epoch_miss(n, m):
  {==}

def main() -> IO(Unit):
  C.Check.str("two canonical signal memo laws", "proved", "proved")
