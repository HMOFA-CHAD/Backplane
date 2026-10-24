import Base
import ./check.bend as C
import ../src/core/client.bend as U
import ../src/core/model.bend as M

# Raw numeric display decoration leaves project/keyboard membership alone.
law signal_given_mine:
  for +ix: U.SIx
  for +u: U.Ui
  for signals: Map<&2, Nat>
  for +pid: String
  {U.SIx.mine(U.Side.signals.ix.given(ix, u, signals), pid) == U.SIx.mine(ix, pid) : List<&2, M.Thread>}

def signal_given_mine(ix, u, signals, pid):
  match ix u:
    case U.SIx{by, asks, kids, work} U.Ui{st, se, dr, li, op, on, now, ad, pa, ve, ri, wa, er, no, nf, ob, tr}: {==}

def main() -> IO(Unit):
  C.Check.str("numeric decoration preserves project membership law", "proved", "proved")
