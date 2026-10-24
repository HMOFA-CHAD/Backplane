import Base
import ./model.bend as M
import ./i18n.bend as I

# Visible activity, separate from persisted turn state and readiness. A result
# owed to an agent is not running work. No clock, transcript, notices, provider
# calls or cache readiness enter this projection. Bits 1/2 record actual work /
# unresolved interaction; 4 is settled only when neither bit is present.
# The index is transient: do not persist it or change the event/state codecs.

def Signal.compose(blocked: Bool, active: Bool, settled: Bool) -> Nat:
  match blocked active settled:
    case True{} True{} _: 3n
    case True{} False{} _: 2n
    case False{} True{} _: 1n
    case False{} False{} True{}: 4n
    case False{} False{} False{}: 0n

def Signal.bits(+n: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_lt(n, 4n), n, 0n)

def Signal.active(+n: Nat) -> Bool:
  Nat.is_eq(Nat.mod(Signal.bits(n), 2n), 1n)

def Signal.blocked(+n: Nat) -> Bool:
  Nat.is_ge(Signal.bits(n), 2n)

def Signal.merge(+a: Nat, +b: Nat) -> Nat:
  Nat.add(Bool.pick(Nat, Bool.or(Signal.active(a), Signal.active(b)), 1n, 0n),
    Bool.pick(Nat, Bool.or(Signal.blocked(a), Signal.blocked(b)), 2n, 0n))

def Signal.name(+n: Nat) -> String:
  Bool.pick(String, Signal.blocked(n), "blocked", Bool.pick(String, Signal.active(n), "active", Bool.pick(String, Nat.is_eq(n, 4n), "settled", "inactive")))

def Signal.label.loc(lc: I.Loc, +name: String) -> String:
  match lc:
    case I.Ja{}:
      Bool.pick(String, String.eq(name, "blocked"), "対応が必要です", Bool.pick(String, String.eq(name, "active"), "作業中", Bool.pick(String, String.eq(name, "settled"), "完了済み", "非稼働・実行中の作業は未確認です")))
    case _:
      Bool.pick(String, String.eq(name, "blocked"), "Blocked: needs interaction", Bool.pick(String, String.eq(name, "active"), "Working: agent or owned work active", Bool.pick(String, String.eq(name, "settled"), "Settled", "Inactive: no confirmed active work")))

def Signal.label(+lc: I.Loc, +n: Nat) -> String:
  Signal.label.loc(lc, Signal.name(n)) ++ Bool.pick(String, Bool.and(Signal.blocked(n), Signal.active(n)),
    Bool.pick(String, String.eq(I.I18n.tag(lc), "ja"), "（実行中の作業もあります）", "; work also active"), "")

def Signal.at.k(r: Map<&2, Nat> & Nat) -> Nat:
  (_, n) = r
  n

def Signal.at(+m: Map<&2, Nat>, +id: String) -> Nat:
  Signal.at.k(Map.get(Nat, 0n, m, id))

def Signal.asks(xs: List<&2, M.Ask>, +m: Map<&2, Nat>) -> Map<&2, Nat>:
  match xs:
    case Nil{}: m
    case M.Ask{_, +th, _, _, _, _, open, _} <> rest:
      Signal.asks(rest, Map.set(&2, Nat, m, th, Bool.pick(Nat, open, 2n, Signal.at(m, th))))

def Signal.failed(t: M.TurnState) -> Bool:
  match t:
    case M.Failed{}: True{}
    case _: False{}

# Watching/cancelling confirm an owned process; launching/queued/unknown do
# not. Ended rows stay in Work.rows until delivery but are never active here.
def Signal.watch(xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}: False{}
    case +l <> rest:
      Bool.or(Bool.and(Bool.not(M.Bg.ended(l)), Bool.or(String.starts_with(M.Bg.doing(l), "watching"), String.eq(M.Bg.doing(l), "cancelling"))), Signal.watch(rest))

def Signal.held(xs: List<&2, M.QItem>) -> Bool:
  match xs:
    case Nil{}: False{}
    case M.QItem{+id, _} <> rest:
      Bool.or(String.starts_with(id, "fallback:held:"), Signal.held(rest))

def Signal.shelf(s: M.Shelf) -> Bool:
  match s:
    case M.Settled{}: True{}
    case _: False{}

def Signal.own(+st: M.State, +asks: Map<&2, Nat>, +t: M.Thread) -> Nat:
  match t:
    case M.Thread{+id, _, _, _, _, +turn, +pending, _, _, _, _, _, _, _, _, _, _, _, _, _, deleted}:
      +owned = Bool.or(Nat.is_gt(M.Bg.running(M.Bg.of(st, id)), 0n), Signal.watch(M.Work.watch(st, id)))
      +blocked = Bool.or(Signal.failed(turn), Bool.or(Nat.is_gt(pending, 0n), Bool.or(Signal.blocked(Signal.at(asks, id)),
        Bool.or(Bool.not(String.is_empty(M.Setting.get(st, "auth.wait." ++ id, ""))), Signal.held(M.Queue.items(st, id))))))
      Bool.pick(Nat, deleted, 0n, Signal.compose(blocked, Bool.or(owned, Bool.and(M.State.running.k(t), Bool.not(blocked))), Signal.shelf(M.Shelf.of(t))))

def Signal.owns(ts: List<&2, M.Thread>, +st: M.State, +asks: Map<&2, Nat>, m: Map<&2, Nat>) -> Map<&2, Nat>:
  match ts:
    case Nil{}: m
    case +t <> rest:
      Signal.owns(rest, st, asks, Map.set(&2, Nat, m, M.Thread.id(t), Signal.own(st, asks, t)))

def Signal.parents.get.k(r: Map<&2, List<&2, String>> & List<&2, String>) -> List<&2, String>:
  (_, xs) = r
  xs

def Signal.parents.get(+m: Map<&2, List<&2, String>>, +id: String) -> List<&2, String>:
  Signal.parents.get.k(Map.get(List<&2, String>, Nil{}, m, id))

def Signal.has.k(r: Map<&2, Nat> & Bool) -> Bool:
  (_, yes) = r
  yes

def Signal.has(+known: Map<&2, Nat>, +id: String) -> Bool:
  Signal.has.k(Map.has(&2, Nat, known, id))

def Signal.edge(ok: Bool, +child: String, +parent: String, +m: Map<&2, List<&2, String>>) -> Map<&2, List<&2, String>>:
  match ok:
    case False{}: m
    case True{}:
      Map.set(&2, List<&2, String>, m, child, parent <> Signal.parents.get(m, child))

def Signal.task.edges(xs: List<&2, M.Task>, +known: Map<&2, Nat>, m: Map<&2, List<&2, String>>) -> Map<&2, List<&2, String>>:
  match xs:
    case Nil{}: m
    case M.Task{_, +p, +c, _, s, _, _, _, _} <> rest:
      Signal.task.edges(rest, known, Signal.edge(Bool.and(Bool.not(M.TaskState.terminal(s)), Bool.and(Signal.has(known, c), Signal.has(known, p))), c, p, m))

def Signal.launch.edges(xs: List<&2, M.Thread>, +st: M.State, +known: Map<&2, Nat>, m: Map<&2, List<&2, String>>) -> Map<&2, List<&2, String>>:
  match xs:
    case Nil{}: m
    case t <> rest:
      +id = M.Thread.id(t)
      +by = M.Launch.by(st, id)
      Signal.launch.edges(rest, st, known, Signal.edge(Bool.and(Bool.not(String.is_empty(by)), Signal.has(known, by)), id, by, m))

type SignalStep is Data:
  SignalStep{values: Map<&2, Nat>, queue: List<&2, String>}

def Signal.changed(changed: Bool, +id: String, +value: Nat, s: SignalStep) -> SignalStep:
  match changed s:
    case False{} _: s
    case True{} SignalStep{m, q}:
      SignalStep{Map.set(&2, Nat, m, id, value), id <> q}

def Signal.spread(xs: List<&2, String>, +bits: Nat, s: SignalStep) -> SignalStep:
  match xs s:
    case Nil{} _: s
    case +id <> rest SignalStep{+m, +q}:
      +old = Signal.at(m, id)
      +value = Signal.merge(old, bits)
      Signal.spread(rest, bits, Signal.changed(Bool.not(Nat.is_eq(Signal.bits(old), value)), id, value, SignalStep{m, q}))

def Signal.step(s: SignalStep, +parents: Map<&2, List<&2, String>>) -> SignalStep:
  match s:
    case SignalStep{m, Nil{}}: SignalStep{m, Nil{}}
    case SignalStep{+m, +id <> q}:
      Signal.spread(Signal.parents.get(parents, id), Signal.bits(Signal.at(m, id)), SignalStep{m, q})

# Each node can acquire each of two bits only once. Three visits per node
# (the initial queue + two upgrades) suffice, including malformed cycles.
def Signal.drain(fuel: Nat, s: SignalStep, +parents: Map<&2, List<&2, String>>) -> SignalStep:
  match fuel s:
    case 0n _: s
    case 1n+_ SignalStep{m, Nil{}}: SignalStep{m, Nil{}}
    case 1n+k SignalStep{m, id <> q}:
      Signal.drain(k, Signal.step(SignalStep{m, id <> q}, parents), parents)

def Signal.values(s: SignalStep) -> Map<&2, Nat>:
  match s:
    case SignalStep{m, _}: m

def Signal.pending(s: SignalStep) -> Nat:
  match s:
    case SignalStep{_, q}: List.length(&2, String, q)

def Signal.ids(xs: List<&2, M.Thread>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case t <> rest: M.Thread.id(t) <> Signal.ids(rest)

def Signal.index.owns(+st: M.State, +ts: List<&2, M.Thread>, tasks: List<&2, M.Task>, +known: Map<&2, Nat>) -> Map<&2, Nat>:
  Signal.values(Signal.drain(Nat.mul(3n, List.length(&2, M.Thread, ts)), SignalStep{known, Signal.ids(ts)},
    Signal.launch.edges(ts, st, known, Signal.task.edges(tasks, known, Map.new(&2, List<&2, String>)))))

def Signal.index.k(+st: M.State, +ts: List<&2, M.Thread>, tasks: List<&2, M.Task>) -> Map<&2, Nat>:
  Signal.index.owns(st, ts, tasks, Signal.owns(ts, st, Signal.asks(M.Asks.all(st), Map.new(&2, Nat)), Map.new(&2, Nat)))

def Signal.index(+st: M.State) -> Map<&2, Nat>:
  match st:
    case M.State{_, ts, _, _, tk, _, _, _, _, _, _}:
      Signal.index.k(st, Map.values(&2, M.Thread, ts), Map.values(&2, M.Task, tk))

def Signal.of(+st: M.State, t: M.Thread) -> Nat:
  Signal.at(Signal.index(st), M.Thread.id(t))

# Reserved values only in a frame's decorated Ui.info and SIx.work.
def Signal.key(+id: String) -> String:
  "@signal:" ++ id

def Signal.visible(online: Bool, +n: Nat) -> Nat:
  match online:
    case True{}: n
    case False{}: Bool.pick(Nat, Signal.active(n), Bool.pick(Nat, Signal.blocked(n), 2n, 0n), n)

def Signal.cache.go(xs: List<&2, String>, +online: Bool, +signals: Map<&2, Nat>, info: Map<&2, String>) -> Map<&2, String>:
  match xs:
    case Nil{}: info
    case +id <> rest:
      Signal.cache.go(rest, online, signals, Map.set(&2, String, info, Signal.key(id), Nat.show(Signal.visible(online, Signal.at(signals, id)))))

def Signal.cache(+online: Bool, +signals: Map<&2, Nat>, info: Map<&2, String>) -> Map<&2, String>:
  Signal.cache.go(Map.keys(&2, Nat, signals), online, signals, Map.set(&2, String, info, "@signal.online", Bool.pick(String, online, "1", "0")))

def Signal.cached.k(r: Map<&2, String> & String) -> Nat:
  (_, v) = r
  M.Switch.num(v, 0n)

def Signal.cached(+info: Map<&2, String>, +id: String) -> Nat:
  Signal.cached.k(Map.get(String, "0", info, Signal.key(id)))

# The server may pass raw bits directly to the display index. Fall back to
# the original info parser if its input was already decorated or has an
# unknown reserved entry, so no legacy value disappears.
def Signal.info.raw.go(xs: List<&2, String>, clean: Bool) -> Bool:
  match xs:
    case Nil{}: clean
    case k <> rest: Signal.info.raw.go(rest, Bool.and(clean, Bool.not(String.starts_with(k, "@signal:"))))

def Signal.info.raw(xs: List<&2, String>) -> Bool:
  Signal.info.raw.go(xs, True{})

def Signal.work.given(xs: List<&2, Sigma<&2, &2, String, _ => Nat>>, +online: Bool, work: Map<&2, Nat>) -> Map<&2, Nat>:
  match xs:
    case Nil{}: work
    case (id, n) <> rest:
      Signal.work.given(rest, online, Map.set(&2, Nat, work, Signal.key(id), Signal.visible(online, n)))

def Signal.cache.put(yes: Bool, +k: String, +info: Map<&2, String>, work: Map<&2, Nat>) -> Map<&2, Nat>:
  match yes:
    case False{}: work
    case True{}:
      Map.set(&2, Nat, work, k, Signal.cached(info, String.drop(k, 8n)))

def Signal.cache.keys(xs: List<&2, String>, +info: Map<&2, String>, work: Map<&2, Nat>) -> Map<&2, Nat>:
  match xs:
    case Nil{}: work
    case +k <> rest:
      Signal.cache.keys(rest, info, Signal.cache.put(String.starts_with(k, "@signal:"), k, info, work))

def Signal.cache.work(+info: Map<&2, String>, work: Map<&2, Nat>) -> Map<&2, Nat>:
  Signal.cache.keys(Map.keys(&2, String, info), info, work)

# LiveActivity counts top-level work, not provider process existence. Its
# legacy calculator accepts Running threads, so adapt only its temporary
# input list. The canonical state, events and notification policy stay raw.
def Signal.island.go(ts: List<&2, M.Thread>, +info: Map<&2, String>, +acc: List<&2, M.Thread>) -> List<&2, M.Thread>:
  match ts:
    case Nil{}: List.reverse(&2, M.Thread, acc)
    case +t <> rest:
      Signal.island.go(rest, info, Bool.pick(List<&2, M.Thread>, Signal.active(Signal.cached(info, M.Thread.id(t))),
        M.Thread.turned(M.Running{}, 0n, t) <> acc, acc))

def Signal.island.threads(ts: List<&2, M.Thread>, info: Map<&2, String>) -> List<&2, M.Thread>:
  Signal.island.go(ts, info, Nil{})
