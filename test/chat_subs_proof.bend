import Base
import ../src/core/model.bend as M
import ../src/core/client.bend as U
import ../src/core/subs.bend as SB

# Universal, independent of any example or cache stamp.
def phase_index(+st: M.State) -> {SB.Subs.index.phase(U.Side.ix(st)) == SB.Subs.index(st) : U.SIx}:
  {==}

def children(+some: Bool, +ts: List<&2, M.Task>, +ids: List<&2, String>, +st: M.State, +now: Nat) ->
  {SB.Subs.children.at(some, ts, ids, st, now, [U.Side.ix(st)]) == SB.Subs.children(some, ts, ids, st, now) : List<&2, SB.SubRow>}:
  match some:
    case False{}: {==}
    case True{}: {==}

def rows(+st: M.State, +info: Map<&2, String>, +th: String, +now: Nat) ->
  {SB.Subs.rows.ix(st, info, th, now, U.Side.ix(st)) == SB.Subs.rows(st, info, th, now) : List<&2, SB.SubRow>}:
  +ts = U.Tasks.of(st, th)
  +ids = M.Launch.of(st, th)
  +some = Bool.or(Bool.not(List.is_empty(&2, M.Task, ts)), Bool.not(List.is_empty(&2, String, ids)))
  Equal.cong(List<&2, SB.SubRow>, List<&2, SB.SubRow>,
    rs => SB.Subs.group(List.concat(&2, SB.SubRow, [rs, SB.Subs.wakes(st, th), SB.Subs.locks.go(M.Locks.names(st), st, th), SB.Subs.agents(st, info, th, now)]), info, th),
    SB.Subs.children.at(some, ts, ids, st, now, [U.Side.ix(st)]),
    SB.Subs.children(some, ts, ids, st, now),
    children(some, ts, ids, st, now))
