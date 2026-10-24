import Base
import ./check.bend as C
import ../src/core/client.bend as U
import ../src/core/model.bend as M

# Fresh row sharing changes neither Active selection nor the project index.
law active_rows_given_eq:
  for +st: M.State
  for +ix: U.SIx
  for +now: Nat
  for +q: String
  {U.Active.rows.given(st, ix, now, q, U.Side.rows.ix(st, ix, now)) == U.Active.rows.ix(st, ix, now, q) : List<&2, U.ARow>}

law side_mine_work_independent:
  for +by: Map<&2, List<&2, M.Thread>>
  for +asks: Map<&2, List<&2, M.Ask>>
  for +kids: Map<&2, Nat>
  for a: Map<&2, Nat>
  for b: Map<&2, Nat>
  for +pid: String
  {U.SIx.mine(U.SIx{by, asks, kids, a}, pid) == U.SIx.mine(U.SIx{by, asks, kids, b}, pid) : List<&2, M.Thread>}

def active_rows_given_eq(st, ix, now, q):
  {==}

def side_mine_work_independent(by, asks, kids, a, b, pid):
  {==}

def main() -> IO(Unit):
  C.Check.str("two fresh projection laws", "proved", "proved")
