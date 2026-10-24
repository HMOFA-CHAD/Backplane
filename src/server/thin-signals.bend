import Base
import ../core/model.bend as M
import ../core/signal.bend as SG

# One private canonical-derived value on a surviving thin actor. No UI,
# recipient info, clock, draft, command or rendered node is retained here.
# The epoch/sequence are server inputs, never renderer acknowledgements.
type SignalCache is Data:
  SignalCache{epoch: String, seq: Nat, signals: Map<&2, Nat>, bounded: Bool}

def SignalCache.signals(c: SignalCache) -> Map<&2, Nat>:
  match c:
    case SignalCache{_, _, signals, _}: signals

def SignalCache.bounded(c: SignalCache) -> Bool:
  match c:
    case SignalCache{_, _, _, bounded}: bounded

def SignalCache.build(epoch: String, seq: Nat, +signals: Map<&2, Nat>) -> SignalCache:
  SignalCache{epoch, seq, signals, Nat.is_le(List.length(&2, String, Map.keys(&2, Nat, signals)), 4096n)}

def SignalCache.hit(c: SignalCache, +epoch: String, +seq: Nat) -> Bool:
  match c:
    case SignalCache{saved, n, _, bounded}:
      Bool.and(bounded, Bool.and(String.eq(saved, epoch), Nat.is_eq(n, seq)))

def SignalCache.choose(hit: Bool, c: SignalCache, epoch: String, seq: Nat, st: M.State) -> SignalCache:
  match hit:
    case True{}: c
    case False{}: SignalCache.build(epoch, seq, SG.Signal.index(st))

def SignalCache.obtain(+epoch: String, +st: M.State, saved: Maybe<&2, SignalCache>) -> SignalCache:
  match saved:
    case None{}: SignalCache.build(epoch, M.State.seq(st), SG.Signal.index(st))
    case Some{+c}: SignalCache.choose(SignalCache.hit(c, epoch, M.State.seq(st)), c, epoch, M.State.seq(st), st)
