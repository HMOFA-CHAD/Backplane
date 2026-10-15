import Base
import ./model.bend as M

# Usage
# -----
# What Settings > Usage says, the same rows in every client. A thread's
# reading (the setting usage.<thread>, from UsageSet) is how much of its
# model's context window the session holds now: a reading, never a total,
# so readings are listed, not summed. Only Claude reports one; a thread on
# another provider says so ("ctx n/a") instead of showing nothing.

type UseT is Data:
  UseT{id: String, title: String, provider: String, model: String, open: Bool, used: Nat, window: Nat}

type URow is Data:
  URow{label: String, note: String}

# whether a provider reports its context (only Claude's stream does)
def Use.reports(+provider: String) -> Bool:
  String.eq(provider, "claude")

def Use.pct(+used: Nat, +window: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_eq(window, 0n), 0n, Nat.div(Nat.mul(used, 100n), window))

def Use.tokens(+n: Nat) -> String:
  Bool.pick(String, Nat.is_ge(n, 1000000n), Nat.show(Nat.div(n, 1000000n)) ++ "M",
    Bool.pick(String, Nat.is_ge(n, 1000n), Nat.show(Nat.div(n, 1000n)) ++ "k", Nat.show(n)))

def Use.tail.k(has: Bool, +provider: String, +text: String) -> String:
  match has:
    case True{}:
      text
    case False{}:
      Bool.pick(String, Use.reports(provider), "", " · ctx n/a")

# the model chip's tail: the reading's text, "ctx n/a" for a provider that
# never reports one, nothing before a reporting provider's first reading
def Use.tail(+provider: String, +used: Nat, +text: String) -> String:
  Use.tail.k(Nat.is_gt(used, 0n), provider, text)

def Use.of.k(t: M.Thread, +v: String) -> UseT:
  match t:
    case M.Thread{id, _, ti, _, _, _, _, ar, _, _, _, _, _, _, _, pr, mo, _, _, _, de}:
      UseT{id, Bool.pick(String, String.is_empty(ti), id, ti), pr, mo, Bool.not(Bool.or(ar, de)), M.Usage.used(v), M.Usage.window(v)}

def Use.of(+st: M.State, t: M.Thread) -> UseT:
  Use.of.k(t, M.Setting.get(st, M.Usage.key(M.Thread.id(t)), ""))

def Use.all(+st: M.State, ts: List<&2, M.Thread>) -> List<&2, UseT>:
  match ts:
    case Nil{}:
      Nil{}
    case t <> r:
      Use.of(st, t) <> Use.all(st, r)

def UseT.open(u: UseT) -> Bool:
  match u:
    case UseT{_, _, _, _, o, _, _}:
      o

def UseT.held(u: UseT) -> Bool:
  match u:
    case UseT{_, _, _, _, o, n, _}:
      Bool.and(o, Nat.is_gt(n, 0n))

def UseT.used(u: UseT) -> Nat:
  match u:
    case UseT{_, _, _, _, _, n, _}:
      n

# fuller first
def UseT.before(a: UseT, b: UseT) -> Bool:
  Nat.is_ge(UseT.used(a), UseT.used(b))

def Use.count(us: List<&2, UseT>, +acc: Nat) -> Nat:
  match us:
    case Nil{}:
      acc
    case _ <> r:
      Use.count(r, Nat.add(acc, 1n))

def Use.held.note(+used: Nat, +window: Nat) -> String:
  Bool.pick(String, Nat.is_eq(window, 0n), Use.tokens(used) ++ " held, window unknown",
    Use.tokens(used) ++ " of " ++ Use.tokens(window) ++ " held (" ++ Nat.show(Use.pct(used, window)) ++ "%)")

def Use.row(u: UseT) -> URow:
  match u:
    case UseT{_, ti, _, mo, _, n, w}:
      URow{ti, Bool.pick(String, String.is_empty(mo), "default", mo) ++ " · " ++ Use.held.note(n, w)}

def Use.rows.t(us: List<&2, UseT>) -> List<&2, URow>:
  match us:
    case Nil{}:
      Nil{}
    case u <> r:
      Use.row(u) <> Use.rows.t(r)

def Use.summary(+held: Nat, +open: Nat) -> URow:
  URow{"Context now", Nat.show(held) ++ " of " ++ Nat.show(open) ++ " open threads have a reading. Only Claude reports one; others show ctx n/a."}

# the fullest open threads' readings, at most `n`
def Use.top(+n: Nat, us: List<&2, UseT>) -> List<&2, URow>:
  Use.rows.t(List.take(&2, UseT, List.sort(~UseT, ~UseT.before, List.filter(~UseT, ~UseT.held, us)), n))

def Use.totals() -> URow:
  URow{"Tokens and cost", "Not recorded yet. A reading is what a session holds now, not what it has used, so readings are not added up."}

def Use.rows.k(+us: List<&2, UseT>) -> List<&2, URow>:
  Use.summary(Use.count(List.filter(~UseT, ~UseT.held, us), 0n), Use.count(List.filter(~UseT, ~UseT.open, us), 0n)) <> List.append(&2, URow, Use.top(8n, us), [Use.totals()])

# Settings > Usage, model side: a summary, the fullest threads, and what is
# not known
def Use.rows(+st: M.State, ts: List<&2, M.Thread>) -> List<&2, URow>:
  Use.rows.k(Use.all(st, ts))

def URow.label(r: URow) -> String:
  match r:
    case URow{l, _}:
      l

def URow.note(r: URow) -> String:
  match r:
    case URow{_, n}:
      n
