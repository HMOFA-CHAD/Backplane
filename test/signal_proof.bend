import Base
import ../src/core/signal.bend as S

# Additive display laws. Existing LAWS/PROOF and saved lifecycle stay intact.
law interaction_first:
  for +active: Bool
  for +settled: Bool
  {S.Signal.name(S.Signal.compose(True{}, active, settled)) == "blocked" : String}

def interaction_first(active, settled):
  match active:
    case True{}: {==}
    case False{}: {==}

law work_before_settled:
  for +settled: Bool
  {S.Signal.name(S.Signal.compose(False{}, True{}, settled)) == "active" : String}

def work_before_settled(settled):
  {==}

law settled_without_work:
  {S.Signal.name(S.Signal.compose(False{}, False{}, True{})) == "settled" : String}

def settled_without_work():
  {==}

law inactive_without_work:
  {S.Signal.name(S.Signal.compose(False{}, False{}, False{})) == "inactive" : String}

def inactive_without_work():
  {==}

law offline_cannot_claim_worker:
  for +blocked: Bool
  for +settled: Bool
  {S.Signal.active(S.Signal.visible(False{}, S.Signal.compose(blocked, True{}, settled))) == False{} : Bool}

def offline_cannot_claim_worker(blocked, settled):
  match blocked:
    case True{}: {==}
    case False{}: {==}

law offline_does_not_resolve_interaction:
  for +active: Bool
  for +settled: Bool
  {S.Signal.blocked(S.Signal.visible(False{}, S.Signal.compose(True{}, active, settled))) == True{} : Bool}

def offline_does_not_resolve_interaction(active, settled):
  match active:
    case True{}: {==}
    case False{}: {==}

law stopped_walk_preserves_pending:
  for +m: Map<&2, Nat>
  for +q: List<&2, String>
  for +p: Map<&2, List<&2, String>>
  {S.Signal.drain(0n, S.SignalStep{m, q}, p) == S.SignalStep{m, q} : S.SignalStep}

def stopped_walk_preserves_pending(m, q, p):
  {==}
