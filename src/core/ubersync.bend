import Base
import ./model.bend as M
import ./bot.bend as BT
import ./json.bend as J
import ./ubop.bend as UO
import ./uber.bend as UB

# One uberbot on several machines (docs/uber.md, "Sync")
# -------------------------------------------------------
# The uberbot is one bot on the owner's linked machines. Each machine keeps
# its own replica (an ordinary local bot, tied to the uberbot's uid by
# UberSet) and a log of ops (UberOp, folded by model.bend as settings
# under the uid, ubop.bend). Everything here is pure: what a machine
# lacks, what an op does to the replica, who holds the conversation, who
# fires a routine. The server (server.bend, "The uberbot's sync") only
# carries the lines between machines.

def Ub.uid(+st: M.State) -> String:
  M.Setting.get(st, "uber.uid", "")

# this machine's id, made once by the server (setting machine.id)
def Ub.me(+st: M.State) -> String:
  M.Setting.get(st, "machine.id", "")

# this machine has an uberbot of its own to sync, and an id to sync under
def Ub.on(+st: M.State) -> Bool:
  Bool.and(Bool.not(String.is_empty(Ub.me(st))), Bool.and(Bool.not(String.is_empty(Ub.uid(st))), Bool.not(String.is_empty(UB.Uber.bot(st)))))

def Ub.vv.of(+st: M.State, +uid: String, +origin: String) -> Nat:
  M.Switch.num(M.Setting.get(st, UO.Ub.key.vv(uid, origin), "0"), 0n)

def Ub.hlc(+st: M.State, +uid: String) -> String:
  M.Setting.get(st, UO.Ub.key.hlc(uid), "")

def Ub.nonempty(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      BT.Post.keep(String, Bool.not(String.is_empty(x)), x, Ub.nonempty(t))

# the machines whose ops this one has
def Ub.origins(+st: M.State, +uid: String) -> List<&2, String>:
  Ub.nonempty(String.split(M.Setting.get(st, UO.Ub.key.origins(uid), ""), ' '))

# What a machine has, and what another lacks
# -------------------------------------------

def Ub.vv.go(os: List<&2, String>, +st: M.State, +uid: String) -> List<&2, J.KV>:
  match os:
    case Nil{}:
      Nil{}
    case +o <> t:
      J.KV{o, J.Json.nat(Ub.vv.of(st, uid, o))} <> Ub.vv.go(t, st, uid)

# the version vector, origin -> highest n, as JSON
def Ub.vv(+st: M.State) -> J.Json:
  J.Json.obj(Ub.vv.go(Ub.origins(st, Ub.uid(st)), st, Ub.uid(st)))

# the most ops of one origin in one exchange (the rest follow in the next)
def Ub.batch() -> Nat:
  64n

def Ub.lack.n(k: Nat, +from: Nat, +st: M.State, +uid: String, +o: String) -> List<&2, String>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      M.Setting.get(st, UO.Ub.key.op(uid, o, from), "") <> Ub.lack.n(p, Nat.add(from, 1n), st, uid, o)

def Ub.cap(+a: Nat, +b: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_le(a, b), a, b)

def Ub.lack.o(os: List<&2, String>, +st: M.State, +uid: String, +vv: J.Json) -> List<&2, String>:
  match os:
    case Nil{}:
      Nil{}
    case +o <> t:
      List.append(&2, String, Ub.lack.n(Ub.cap(Nat.sub(Ub.vv.of(st, uid, o), UO.Ub.nat(vv, o)), Ub.batch()), Nat.add(UO.Ub.nat(vv, o), 1n), st, uid, o),
        Ub.lack.o(t, st, uid, vv))

# the op lines another machine (whose version vector is `vv`) lacks, oldest
# first within each origin
def Ub.lacking(+st: M.State, +vv: J.Json) -> List<&2, String>:
  Ub.lack.o(Ub.origins(st, Ub.uid(st)), st, Ub.uid(st), vv)

# Making ops
# ----------

def Ub.ops.go(bs: List<&2, String>, +uid: String, +me: String, +n: Nat, +last: String, +now: Nat) -> List<&2, M.Change>:
  match bs:
    case Nil{}:
      Nil{}
    case +b <> t:
      M.UberOp{uid, me, n, UO.Ub.stamp.next(last, now, me), b, now} <> Ub.ops.go(t, uid, me, Nat.add(n, 1n), UO.Ub.stamp.next(last, now, me), now)

def Ub.ops.with.k(ok: Bool, bs: List<&2, String>, +st: M.State, +uid: String, +now: Nat) -> List<&2, M.Change>:
  match ok:
    case True{}:
      Ub.ops.go(bs, uid, Ub.me(st), Nat.add(Ub.vv.of(st, uid, Ub.me(st)), 1n), Ub.hlc(st, uid), now)
    case False{}:
      Nil{}

# the ops for these bodies, as this machine's next ones, under `uid` (not
# yet the state's: a promotion makes its first before the fold of UberSet)
def Ub.ops.with(+st: M.State, +uid: String, +now: Nat, bs: List<&2, String>) -> List<&2, M.Change>:
  Ub.ops.with.k(Bool.and(Bool.not(String.is_empty(Ub.me(st))), Bool.not(String.is_empty(uid))), bs, st, uid, now)

def Ub.ops(+st: M.State, +now: Nat, bs: List<&2, String>) -> List<&2, M.Change>:
  Ub.ops.with(st, Ub.uid(st), now, bs)

# The conversation's lease
# ------------------------

type Lease is Data:
  Lease{holder: String, term: Nat}

def Ub.lease.of(+o: J.Json) -> Lease:
  Lease{UO.Ub.field(o, "holder"), UO.Ub.nat(o, "term")}

def Ub.lease(+st: M.State) -> Lease:
  Ub.lease.of(UO.Ub.json(M.Setting.get(st, UO.Ub.key.reg(Ub.uid(st), "lease"), "")))

def Lease.holder(l: Lease) -> String:
  match l:
    case Lease{h, _}:
      h

def Lease.term(l: Lease) -> Nat:
  match l:
    case Lease{_, t}:
      t

# the machine that holds the uberbot's conversation ("" before any lease)
def Ub.holder(+st: M.State) -> String:
  Lease.holder(Ub.lease(st))

def Ub.term(+st: M.State) -> Nat:
  Lease.term(Ub.lease(st))

# this machine holds the conversation (and so, with no lease yet, the
# only machine there is does)
def Ub.holder.me(+st: M.State) -> Bool:
  Bool.or(String.is_empty(Ub.holder(st)), String.eq(Ub.holder(st), Ub.me(st)))

# Routines
# --------

# a routine's id across machines: "<origin>:<local id>"; a local id that
# has a machine in it already is one
def Ub.gid(+me: String, +id: String) -> String:
  Bool.pick(String, String.contains(id, ":"), id, me ++ ":" ++ id)

# the local id of a routine across machines
def Ub.lid(+me: String, +gid: String) -> String:
  Bool.pick(String, String.starts_with(gid, me ++ ":"), String.drop(gid, Nat.add(String.length(me), 1n)), gid)

def Ub.pin(+st: M.State, +gid: String) -> String:
  UO.Ub.field(UO.Ub.json(M.Setting.get(st, UO.Ub.key.reg(Ub.uid(st), "routine:" ++ gid), "")), "pin")

# the highest slot a routine ran for (0: never)
def Ub.fired(+st: M.State, +gid: String) -> Nat:
  M.Switch.num(M.Setting.get(st, UO.Ub.key.fired(Ub.uid(st), gid), "0"), 0n)

def Ub.fires.k(pinned: Bool, mine: Bool, holder: Bool, fresh: Bool) -> Bool:
  Bool.and(fresh, Bool.pick(Bool, pinned, mine, holder))

# whether this machine runs the routine (global id `gid`) for this slot: a
# pinned routine only on its machine, any other only on the conversation's
# holder, and a slot only once (a slot not later than one that ran is over)
def Ub.fires(+st: M.State, +gid: String, +slot: Nat) -> Bool:
  Ub.fires.k(Bool.not(String.is_empty(Ub.pin(st, gid))), String.eq(Ub.pin(st, gid), Ub.me(st)), Ub.holder.me(st), Nat.is_gt(slot, Ub.fired(st, gid)))

def Ub.cmp(a: String, b: String) -> Cmp:
  UO.Ub.stamp.cmp(a, b)

# Taking the lease
# ----------------

# whether this machine is first of the machines that answer (the holder
# is not asked): no other id is less than its own
def Ub.first(ids: List<&2, String>, +me: String, +holder: String) -> Bool:
  match ids:
    case Nil{}:
      True{}
    case +i <> t:
      Bool.and(Bool.or(Bool.or(String.is_empty(i), String.eq(i, holder)), Bool.not(Cmp.is_lt(Ub.cmp(i, me)))), Ub.first(t, me, holder))

# the holder has been quiet for the grace and this machine is first of
# those it can reach: it takes the lease
def Ub.takeover(+st: M.State, +heard_ago: Nat, +grace: Nat, first: Bool) -> Bool:
  Bool.and(Bool.and(Ub.on(st), Bool.not(Ub.holder.me(st))), Bool.and(Nat.is_ge(heard_ago, grace), first))

# the body of the lease this machine takes (one term on)
def Ub.lease.body(+st: M.State) -> String:
  UO.Ub.b.lease(Ub.me(st), Nat.add(Ub.term(st), 1n))

# seconds a holder may be quiet before another machine takes over
def Ub.grace() -> Nat:
  600n

def Ub.kind.at(ks: List<&2, String>, +k: String, +i: Nat) -> Nat:
  match ks:
    case Nil{}:
      i
    case +h <> t:
      Bool.pick(Nat, String.eq(h, k), i, Ub.kind.at(t, k, Nat.add(i, 1n)))

# What an op does to the replica
# ------------------------------

# the op's kind as a number (10: not one of ours)
def Ub.kind.n(+k: String) -> Nat:
  Ub.kind.at(["mem", "forget", "space", "page", "who", "routine", "routine-del", "fired", "lease", "bind"], k, 0n)

def Ub.taken.k(on: Bool, +uid: String, +origin: String, +n: Nat, +st: M.State) -> Bool:
  Bool.and(Bool.and(on, String.eq(uid, Ub.uid(st))), Bool.and(Bool.not(String.is_empty(origin)), Nat.is_eq(n, Nat.add(Ub.vv.of(st, uid, origin), 1n))))

# the op is the next one of its origin, under this machine's uberbot, and
# there is a replica to apply it to
def Ub.taken(+st: M.State, +o: UO.UOp) -> Bool:
  Ub.taken.k(Ub.on(st), UO.UOp.uid(o), UO.UOp.origin(o), UO.UOp.n(o), st)

def Ub.wins.k(fired: Bool, +st: M.State, +o: J.Json, +op: String, +stamp: String, +key: String) -> Bool:
  match fired:
    case True{}:
      Nat.is_gt(UO.Ub.nat(o, "slot"), Ub.fired(st, UO.Ub.field(o, "routine")))
    case False{}:
      Bool.and(Bool.not(String.is_empty(key)), UO.Ub.newer(key, op, stamp, M.Setting.get(st, UO.Ub.key.reg(Ub.uid(st), key), ""), M.Setting.get(st, UO.Ub.key.stamp(Ub.uid(st), key), "")))

# the op beats what its register holds (a fired op: a later slot)
def Ub.wins(+st: M.State, +o: J.Json, +op: String, +stamp: String) -> Bool:
  Ub.wins.k(String.eq(UO.Ub.field(o, "k"), "fired"), st, o, op, stamp, UO.Ub.op.key(op))

# the changes to the replica when the op wins; none when it loses (and
# never an op: what is derived from another machine's op is not made
# again as one)
def Ub.derive.n(n: Nat, +b: String, +me: String, +o: J.Json, +at: Nat) -> List<&2, M.Change>:
  match n:
    case 0n:
      [M.MemorySaved{b, UO.Ub.field(o, "key"), UO.Ub.field(o, "kind"), UO.Ub.field(o, "text"), UO.Ub.field(o, "tags"), at}]
    case 1n:
      [M.MemoryForgot{b, UO.Ub.field(o, "key"), at}]
    case 2n:
      [M.SpaceSet{b, UO.Ub.field(o, "spec"), at}]
    case 3n:
      [M.SpacePageSet{b, UO.Ub.field(o, "html"), at}]
    case 4n:
      [M.BotSet{b, UO.Ub.field(o, "name"), "", UO.Ub.nat(o, "look"), UO.Ub.field(o, "persona"), at}]
    case 5n:
      [M.RoutineSet{Ub.lid(me, UO.Ub.field(o, "id")), b, UO.Ub.field(o, "name"), UO.Ub.field(o, "cron"), UO.Ub.field(o, "prompt"), J.Json.get_bool(o, "on", True{}), at}]
    case 6n:
      [M.RoutineDeleted{Ub.lid(me, UO.Ub.field(o, "id")), at}]
    case 7n:
      [M.RoutineFired{Ub.lid(me, UO.Ub.field(o, "routine")), at}]
    case _:
      Nil{}

def Ub.derive.k(win: Bool, +st: M.State, +o: J.Json, +at: Nat) -> List<&2, M.Change>:
  match win:
    case True{}:
      Ub.derive.n(Ub.kind.n(UO.Ub.field(o, "k")), UB.Uber.bot(st), Ub.me(st), o, at)
    case False{}:
      Nil{}

def Ub.derive.o(+st: M.State, +op: String, +stamp: String, +at: Nat) -> List<&2, M.Change>:
  Ub.derive.k(Ub.wins(st, UO.Ub.json(op), op, stamp), st, UO.Ub.json(op), at)

def Ub.derive(+st: M.State, +o: UO.UOp) -> List<&2, M.Change>:
  Ub.derive.o(st, UO.UOp.op(o), UO.UOp.stamp(o), UO.UOp.at(o))

# A routine that ran on two machines for one slot
# -----------------------------------------------

def Ub.dup.text(+st: M.State, +o: J.Json, +origin: String) -> String:
  "routine " ++ UO.Ub.field(UO.Ub.json(M.Setting.get(st, UO.Ub.key.reg(Ub.uid(st), "routine:" ++ UO.Ub.field(o, "routine")), "")), "name") ++
    " ran on both " ++ M.Setting.get(st, UO.Ub.key.by(Ub.uid(st), UO.Ub.field(o, "routine")), "") ++ " and " ++ origin ++ " for " ++ Nat.show(UO.Ub.nat(o, "slot"))

def Ub.dup.is(+st: M.State, +o: J.Json, +origin: String) -> Bool:
  Bool.and(Bool.and(String.eq(UO.Ub.field(o, "k"), "fired"), Nat.is_gt(Ub.fired(st, UO.Ub.field(o, "routine")), 0n)),
    Bool.and(Nat.is_eq(UO.Ub.nat(o, "slot"), Ub.fired(st, UO.Ub.field(o, "routine"))),
      Bool.not(String.eq(M.Setting.get(st, UO.Ub.key.by(Ub.uid(st), UO.Ub.field(o, "routine")), ""), origin))))

def Ub.dup.k(dup: Bool, +st: M.State, +o: J.Json, +origin: String, +n: Nat, +at: Nat) -> List<&2, M.Change>:
  match dup:
    case True{}:
      [M.ActivityLogged{BT.Bot.thread(BT.World.bot(M.State.bots(st), UB.Uber.bot(st))), "ubdup-" ++ origin ++ "-" ++ Nat.show(n), "info", "routine", Ub.dup.text(st, o, origin), at}]
    case False{}:
      Nil{}

# an activity line in the uberbot's thread when a fired op repeats a slot
# another machine already ran
def Ub.dup(+st: M.State, +o: UO.UOp) -> List<&2, M.Change>:
  Ub.dup.k(Ub.dup.is(st, UO.Ub.json(UO.UOp.op(o)), UO.UOp.origin(o)), st, UO.Ub.json(UO.UOp.op(o)), UO.UOp.origin(o), UO.UOp.n(o), UO.UOp.at(o))

# Taking ops in
# -------------

def Ub.change(+o: UO.UOp) -> M.Change:
  M.UberOp{UO.UOp.uid(o), UO.UOp.origin(o), UO.UOp.n(o), UO.UOp.stamp(o), UO.UOp.op(o), UO.UOp.at(o)}

# the changes for one op line that is the next of its origin: it, what it
# does to the replica, and a note when it ran a slot that another machine ran
def Ub.cs(taken: Bool, +o: UO.UOp, +st: M.State) -> List<&2, M.Change>:
  match taken:
    case True{}:
      Ub.change(o) <> List.append(&2, M.Change, Ub.derive(st, o), Ub.dup(st, o))
    case False{}:
      Nil{}

def Ub.adv(taken: Bool, +o: UO.UOp, +st: M.State) -> M.State:
  match taken:
    case True{}:
      M.State.apply(st, Ub.change(o))
    case False{}:
      st

def Ub.parse(ls: List<&2, String>) -> List<&2, UO.UOp>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      UO.Ub.line.read(l) <> Ub.parse(t)

# the changes for ops from another machine, in order: each one that is the
# next of its origin is logged with what it does to the replica; the rest
# (already had, out of order, another uberbot's) change nothing
def Ub.commit.go(os: List<&2, UO.UOp>, +st: M.State) -> List<&2, M.Change>:
  match os:
    case Nil{}:
      Nil{}
    case +o <> t:
      List.append(&2, M.Change, Ub.cs(Ub.taken(st, o), o, st), Ub.commit.go(t, Ub.adv(Ub.taken(st, o), o, st)))

def Ub.commit(ls: List<&2, String>, +st: M.State) -> List<&2, M.Change>:
  Ub.commit.go(Ub.parse(ls), st)
