import Base
import ./json.bend as J

# The uberbot's op log, the part model.bend folds (docs/uber.md)
# ----------------------------------------------------------------
# Pure strings and JSON only: model.bend imports this, so it cannot import
# model.bend. The rest of the sync (derive, lease, fires...) is in
# ubersync.bend.
#
# An op is made on one machine (its origin), numbered 1, 2, ... there (n),
# and stamped with a hybrid logical clock "<secs 10 digits>.<counter 6
# digits>.<origin>": zero-padded, so string order is time order, and equal
# times are told apart by the counter and then the origin. Every op of a
# machine has its own stamp.

# a count written in decimal (Nat.read is slow to check in laws)
def Ub.num(s: String, +acc: Nat) -> Nat:
  match s:
    case SNil{}:
      acc
    case SCon{Chr{+c}, t}:
      Ub.num(t, Nat.add(Nat.mul(acc, 10n), U32.to_nat((c - 48 : U32))))

def Ub.pad(+s: String, +w: Nat) -> String:
  String.repeat("0", Nat.sub(w, String.length(s))) ++ s

def Ub.stamp.make(+secs: Nat, +ctr: Nat, +me: String) -> String:
  Ub.pad(Nat.show(secs), 10n) ++ "." ++ Ub.pad(Nat.show(ctr), 6n) ++ "." ++ me

def Ub.stamp.secs(+s: String) -> Nat:
  Ub.num(String.take(s, 10n), 0n)

def Ub.stamp.ctr(+s: String) -> Nat:
  Ub.num(String.take(String.drop(s, 11n), 6n), 0n)

def Ub.stamp.next.k(later: Bool, +ls: Nat, +lc: Nat, +now: Nat, +me: String) -> String:
  Bool.pick(String, later, Ub.stamp.make(ls, Nat.add(lc, 1n), me), Ub.stamp.make(now, 0n, me))

# the stamp of an op made at `now` by `me`, after the newest stamp seen
# (last, "" for none): never behind it, never equal to it
def Ub.stamp.next(+last: String, +now: Nat, +me: String) -> String:
  Ub.stamp.next.k(Nat.is_ge(Ub.stamp.secs(last), now), Ub.stamp.secs(last), Ub.stamp.ctr(last), now, me)

def Ub.cmp.fin(r: (String & String) & Cmp) -> Cmp:
  ((_a, _b), c) = r
  c

def Ub.stamp.cmp(a: String, b: String) -> Cmp:
  Ub.cmp.fin(String.cmp(a, b))

# a is later than b
def Ub.stamp.gt(a: String, b: String) -> Bool:
  Cmp.is_gt(Ub.stamp.cmp(a, b))

# Op bodies
# ---------

def Ub.json(+s: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(s), J.Null{})

def Ub.field(+o: J.Json, +k: String) -> String:
  J.Json.get_str(o, k, "")

def Ub.nat(+o: J.Json, +k: String) -> Nat:
  Ub.num(J.Json.as_raw(J.Json.get(o, k), ""), 0n)

def Ub.op.kind(+op: String) -> String:
  Ub.field(Ub.json(op), "k")

# 0 mem/forget, 1 routine, 2 bind, 3 a single register, 4 none
def Ub.op.key.n(+k: String) -> Nat:
  Bool.pick(Nat, Bool.or(String.eq(k, "mem"), String.eq(k, "forget")), 0n,
    Bool.pick(Nat, Bool.or(String.eq(k, "routine"), String.eq(k, "routine-del")), 1n,
      Bool.pick(Nat, String.eq(k, "bind"), 2n,
        Bool.pick(Nat, Bool.or(Bool.or(String.eq(k, "space"), String.eq(k, "page")), Bool.or(String.eq(k, "who"), String.eq(k, "lease"))), 3n, 4n))))

def Ub.op.key.m(n: Nat, +k: String, +o: J.Json) -> String:
  match n:
    case 0n:
      "mem:" ++ Ub.field(o, "key")
    case 1n:
      "routine:" ++ Ub.field(o, "id")
    case 2n:
      "bind:" ++ Ub.field(o, "machine")
    case 3n:
      k
    case _:
      ""

# the register an op writes ("" for the ones that write none: fired)
def Ub.op.key.k(+k: String, +o: J.Json) -> String:
  Ub.op.key.m(Ub.op.key.n(k), k, o)

def Ub.op.key(+op: String) -> String:
  Ub.op.key.k(Ub.op.kind(op), Ub.json(op))

# Keys in the settings (all under the uberbot's uid, so a new uberbot
# starts from nothing)
# ------------------------------------------------------------------

def Ub.key.vv(+uid: String, +origin: String) -> String:
  "uber.vv." ++ uid ++ "." ++ origin

def Ub.key.op(+uid: String, +origin: String, +n: Nat) -> String:
  "uber.op." ++ uid ++ "." ++ origin ++ "." ++ Nat.show(n)

def Ub.key.reg(+uid: String, +key: String) -> String:
  "uber.r." ++ uid ++ "." ++ key

def Ub.key.stamp(+uid: String, +key: String) -> String:
  "uber.rs." ++ uid ++ "." ++ key

def Ub.key.fired(+uid: String, +gid: String) -> String:
  "uber.fired." ++ uid ++ "." ++ gid

def Ub.key.by(+uid: String, +gid: String) -> String:
  "uber.firedby." ++ uid ++ "." ++ gid

def Ub.key.origins(+uid: String) -> String:
  "uber.origins." ++ uid

def Ub.key.hlc(+uid: String) -> String:
  "uber.hlc." ++ uid

# Whether an op beats what its register holds
# -------------------------------------------
# Later stamp wins. The lease is ordered by its term first: a higher term
# beats a later stamp (two machines taking the same term are told apart by
# the stamp, so every machine ends with the same holder).

def Ub.newer.lease(o: Cmp, +nst: String, +ost: String) -> Bool:
  match o:
    case GT{}:
      True{}
    case LT{}:
      False{}
    case EQ{}:
      Ub.stamp.gt(nst, ost)

def Ub.newer.k(empty: Bool, lease: Bool, +nt: Nat, +ot: Nat, +nst: String, +ost: String) -> Bool:
  match empty:
    case True{}:
      True{}
    case False{}:
      Bool.pick(Bool, lease, Ub.newer.lease(Nat.cmp(nt, ot), nst, ost), Ub.stamp.gt(nst, ost))

def Ub.newer.t(lease: Bool, empty: Bool, +nop: String, +nst: String, +oop: String, +ost: String) -> Bool:
  match lease:
    case True{}:
      Ub.newer.k(empty, True{}, Ub.nat(Ub.json(nop), "term"), Ub.nat(Ub.json(oop), "term"), nst, ost)
    case False{}:
      Ub.newer.k(empty, False{}, 0n, 0n, nst, ost)

# `key` is the register, nop/nst the op and its stamp, oop/ost what it holds
def Ub.newer(+key: String, +nop: String, +nst: String, +oop: String, +ost: String) -> Bool:
  Ub.newer.t(String.eq(key, "lease"), String.is_empty(ost), nop, nst, oop, ost)

# One op as a line (what a machine keeps and sends)
# -------------------------------------------------

type UOp is Data:
  UOp{uid: String, origin: String, n: Nat, stamp: String, op: String, at: Nat}

def Ub.line(+uid: String, +origin: String, +n: Nat, +stamp: String, +op: String, +at: Nat) -> String:
  J.Json.show(J.Json.obj([J.KV{"u", J.Str{uid}}, J.KV{"o", J.Str{origin}}, J.KV{"n", J.Json.nat(n)}, J.KV{"s", J.Str{stamp}},
    J.KV{"op", J.Str{op}}, J.KV{"at", J.Json.nat(at)}]))

def Ub.line.of(+o: J.Json) -> UOp:
  UOp{Ub.field(o, "u"), Ub.field(o, "o"), Ub.nat(o, "n"), Ub.field(o, "s"), Ub.field(o, "op"), Ub.nat(o, "at")}

# an unreadable line has no origin
def Ub.line.read(+line: String) -> UOp:
  Ub.line.of(Ub.json(line))

def UOp.origin(o: UOp) -> String:
  match o:
    case UOp{_, x, _, _, _, _}:
      x

def UOp.n(o: UOp) -> Nat:
  match o:
    case UOp{_, _, x, _, _, _}:
      x

def UOp.uid(o: UOp) -> String:
  match o:
    case UOp{x, _, _, _, _, _}:
      x

def UOp.stamp(o: UOp) -> String:
  match o:
    case UOp{_, _, _, x, _, _}:
      x

def UOp.op(o: UOp) -> String:
  match o:
    case UOp{_, _, _, _, x, _}:
      x

def UOp.at(o: UOp) -> Nat:
  match o:
    case UOp{_, _, _, _, _, x}:
      x

# Bodies (compact JSON)
# ---------------------

def Ub.b.mem(+key: String, +kind: String, +text: String, +tags: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"k", J.Str{"mem"}}, J.KV{"key", J.Str{key}}, J.KV{"kind", J.Str{kind}}, J.KV{"text", J.Str{text}}, J.KV{"tags", J.Str{tags}}]))

def Ub.b.forget(+key: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"k", J.Str{"forget"}}, J.KV{"key", J.Str{key}}]))

def Ub.b.space(+spec: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"k", J.Str{"space"}}, J.KV{"spec", J.Str{spec}}]))

def Ub.b.page(+html: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"k", J.Str{"page"}}, J.KV{"html", J.Str{html}}]))

def Ub.b.who(+name: String, +look: Nat, +persona: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"k", J.Str{"who"}}, J.KV{"name", J.Str{name}}, J.KV{"look", J.Json.nat(look)}, J.KV{"persona", J.Str{persona}}]))

def Ub.b.routine(+id: String, +name: String, +cron: String, +prompt: String, +on: Bool, +pin: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"k", J.Str{"routine"}}, J.KV{"id", J.Str{id}}, J.KV{"name", J.Str{name}}, J.KV{"cron", J.Str{cron}},
    J.KV{"prompt", J.Str{prompt}}, J.KV{"on", J.Flag{on}}, J.KV{"pin", J.Str{pin}}]))

def Ub.b.routine_del(+id: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"k", J.Str{"routine-del"}}, J.KV{"id", J.Str{id}}]))

def Ub.b.fired(+routine: String, +slot: Nat) -> String:
  J.Json.show(J.Json.obj([J.KV{"k", J.Str{"fired"}}, J.KV{"routine", J.Str{routine}}, J.KV{"slot", J.Json.nat(slot)}]))

def Ub.b.lease(+holder: String, +term: Nat) -> String:
  J.Json.show(J.Json.obj([J.KV{"k", J.Str{"lease"}}, J.KV{"holder", J.Str{holder}}, J.KV{"term", J.Json.nat(term)}]))

def Ub.b.bind(+machine: String, +bot: String, +thread: String, +name: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"k", J.Str{"bind"}}, J.KV{"machine", J.Str{machine}}, J.KV{"bot", J.Str{bot}}, J.KV{"thread", J.Str{thread}},
    J.KV{"name", J.Str{name}}]))

# the origins list (space separated) with one more, kept sorted so the same
# ops in any order leave the same list
def Ub.le(a: String, b: String) -> Bool:
  Cmp.is_le(Ub.stamp.cmp(a, b))

def Ub.origins.keep(hit: Bool, x: String, rest: List<&2, String>) -> List<&2, String>:
  match hit:
    case True{}:
      x <> rest
    case False{}:
      rest

def Ub.origins.nonempty(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      Ub.origins.keep(Bool.not(String.is_empty(x)), x, Ub.origins.nonempty(t))

def Ub.origins.add(+cur: String, +o: String) -> String:
  String.join(List.sort(~String, ~Ub.le, o <> Ub.origins.nonempty(String.split(cur, ' '))), " ")

# Compaction: the op that held a register before a later one wrote it, and an
# op that lost, are kept as a nop (same uid, origin, n and stamp; no body),
# so n stays contiguous and a peer that lacks them still counts them
def Ub.key.rn(+uid: String, +key: String) -> String:
  "uber.rn." ++ uid ++ "." ++ key

def Ub.nop() -> String:
  "{\"k\":\"nop\"}"

def Ub.line.nop(+uid: String, +origin: String, +n: Nat, +stamp: String) -> String:
  Ub.line(uid, origin, n, stamp, Ub.nop(), 0n)
