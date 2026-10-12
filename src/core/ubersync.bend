import Base
import ./model.bend as M
import ./bot.bend as BT
import ./json.bend as J
import ./ubop.bend as UO
import ./uber.bend as UB
import ./far.bend as FR

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

# Making ops from what the uberbot does
# -------------------------------------
# A change to the uberbot's memory, space, page, name or look, or to one
# of its routines, made on this machine (by its own tools or a client) goes
# to the log with an op. Changes derived from another machine's ops never
# come through here.

def Ub.rbot(+st: M.State, +id: String) -> String:
  BT.Routine.bot(BT.World.routine(M.State.bots(st), id))

def Ub.body.routine(+st: M.State, +id: String, +name: String, +cron: String, +prompt: String, +on: Bool) -> String:
  UO.Ub.b.routine(Ub.gid(Ub.me(st), id), name, cron, prompt, on, Ub.pin(st, Ub.gid(Ub.me(st), id)))

def Ub.body.k(mine: Bool, b: String) -> List<&2, String>:
  Bool.pick(List<&2, String>, mine, [b], Nil{})

# the op bodies one local change calls for (none for a change that is not
# the uberbot's)
def Ub.body(+st: M.State, +c: M.Change) -> List<&2, String>:
  match c:
    case M.MemorySaved{+bot, +key, +kind, +text, +tags, _}:
      Ub.body.k(UB.Uber.is(st, bot), UO.Ub.b.mem(key, kind, text, tags))
    case M.MemoryForgot{+bot, +key, _}:
      Ub.body.k(UB.Uber.is(st, bot), UO.Ub.b.forget(key))
    case M.SpaceSet{+bot, +spec, _}:
      Ub.body.k(UB.Uber.is(st, bot), UO.Ub.b.space(spec))
    case M.SpacePageSet{+bot, +html, _}:
      Ub.body.k(UB.Uber.is(st, bot), UO.Ub.b.page(html))
    case M.BotSet{+id, +name, _, +look, +persona, _}:
      Ub.body.k(UB.Uber.is(st, id), UO.Ub.b.who(name, look, persona))
    case M.RoutineSet{+id, +bot, +name, +cron, +prompt, +on, _}:
      Ub.body.k(UB.Uber.is(st, bot), Ub.body.routine(st, id, name, cron, prompt, on))
    case M.RoutineDeleted{+id, _}:
      Ub.body.k(UB.Uber.is(st, Ub.rbot(st, id)), UO.Ub.b.routine_del(Ub.gid(Ub.me(st), id)))
    case _:
      Nil{}

def Ub.bodies(cs: List<&2, M.Change>, +st: M.State) -> List<&2, String>:
  match cs:
    case Nil{}:
      Nil{}
    case +c <> t:
      List.append(&2, String, Ub.body(st, c), Ub.bodies(t, st))

# the changes and, after them, the ops they call for
def Ub.also(+st: M.State, +now: Nat, +cs: List<&2, M.Change>) -> List<&2, M.Change>:
  List.append(&2, M.Change, cs, Ub.ops(st, now, Ub.bodies(cs, st)))

# a routine pinned to a machine ("" takes the pin off): the op alone
def Ub.pin.set.k(mine: Bool, r: BT.Routine, +st: M.State, +now: Nat, +gid: String, +pin: String) -> List<&2, M.Change>:
  match r:
    case BT.Routine{_, _, +name, +cron, +prompt, +on, _, _, _}:
      Bool.pick(List<&2, M.Change>, mine, Ub.ops(st, now, [UO.Ub.b.routine(gid, name, cron, prompt, on, pin)]), Nil{})

def Ub.pin.set(+st: M.State, +now: Nat, +id: String, +pin: String) -> List<&2, M.Change>:
  Ub.pin.set.k(UB.Uber.is(st, Ub.rbot(st, id)), BT.World.routine(M.State.bots(st), id), st, now, Ub.gid(Ub.me(st), id), pin)

# The first ops of an uberbot
# ---------------------------
# Promoted here, it logs everything it has so a machine that joins gets it
# from the log: its name and look, each memory, its space and page, its
# routines, that it holds the conversation (term 1) and where it lives.

def Ub.init.mem(ms: List<&2, BT.Mem>) -> List<&2, String>:
  match ms:
    case Nil{}:
      Nil{}
    case BT.Mem{_, +key, +kind, +text, +tags, _, _} <> t:
      UO.Ub.b.mem(key, kind, text, tags) <> Ub.init.mem(t)

def Ub.init.routines(rs: List<&2, BT.Routine>, +me: String) -> List<&2, String>:
  match rs:
    case Nil{}:
      Nil{}
    case BT.Routine{+id, _, +name, +cron, +prompt, +on, _, _, _} <> t:
      UO.Ub.b.routine(Ub.gid(me, id), name, cron, prompt, on, "") <> Ub.init.routines(t, me)

def Ub.init.opt(+yes: Bool, +b: String) -> List<&2, String>:
  Bool.pick(List<&2, String>, yes, [b], Nil{})

def Ub.init.bot(b: BT.Bot, +st: M.State, +me: String) -> List<&2, String>:
  match b:
    case BT.Bot{+id, +name, +th, +look, +persona, _, _}:
      List.concat(&2, String, [[UO.Ub.b.who(name, look, persona)], Ub.init.mem(BT.World.mems(M.State.bots(st), id)),
        Ub.init.opt(Bool.not(String.is_empty(BT.World.space(M.State.bots(st), id))), UO.Ub.b.space(BT.World.space(M.State.bots(st), id))),
        Ub.init.opt(Bool.not(String.is_empty(BT.Page.html(BT.World.spage(M.State.bots(st), id)))), UO.Ub.b.page(BT.Page.html(BT.World.spage(M.State.bots(st), id)))),
        Ub.init.routines(BT.World.routines(M.State.bots(st), id), me),
        [UO.Ub.b.lease(me, 1n), UO.Ub.b.bind(me, id, th, name)]])

def Ub.init.bodies(+st: M.State, +bot: String) -> List<&2, String>:
  Ub.init.bot(BT.World.bot(M.State.bots(st), bot), st, Ub.me(st))

def Ub.init.k(go: Bool, +st: M.State, +now: Nat) -> List<&2, M.Change>:
  match go:
    case True{}:
      Ub.ops(st, now, Ub.init.bodies(st, UB.Uber.bot(st)))
    case False{}:
      Nil{}

# the ops of an uberbot that has none yet (promoted before this machine had
# an id, or before ops existed); the ones of a machine that joined have its
# bind already and are left alone
def Ub.init(+st: M.State, +now: Nat) -> List<&2, M.Change>:
  Ub.init.k(Bool.and(Ub.on(st), Nat.is_eq(Ub.vv.of(st, Ub.uid(st), Ub.me(st)), 0n)), st, now)

# a bot made the uberbot at `now` under `uid`: UberSet, then its ops (the
# state is the one before UberSet)
def Ub.promoted(+st: M.State, +bot: String, +uid: String, +now: Nat) -> List<&2, M.Change>:
  M.UberSet{bot, uid, now} <> Ub.ops.with(st, uid, now, Ub.init.bodies(st, bot))

# Joining
# -------
# A machine with no uberbot is offered one (setting uber.offer, JSON {uid,
# name, look, machine, link}): joining makes a replica bot with that name
# and look, ties it to the uid and says where it lives; the first exchange
# fills it from the others' ops.

def Ub.offer(+st: M.State) -> J.Json:
  UO.Ub.json(M.Setting.get(st, "uber.offer", ""))

type Join is Data:
  Join{err: String, name: String, look: Nat}

def Ub.join.k(on: Bool, some: Bool, have: Bool, +name: String, +look: Nat) -> Join:
  match on some have:
    case True{} True{} False{}:
      Join{"", name, look}
    case True{} True{} True{}:
      Join{"this machine has an uberbot already; make it not the uberbot first", name, look}
    case _ _ _:
      Join{"that uberbot is not on offer here", name, look}

def Ub.join.of(+o: J.Json, +uid: String, +have: String) -> Join:
  Ub.join.k(String.eq(UO.Ub.field(o, "uid"), uid), Bool.not(String.is_empty(uid)), Bool.not(String.is_empty(have)), UO.Ub.field(o, "name"), UO.Ub.nat(o, "look"))

# can this machine join `uid`: an error text, or the name and look
def Ub.join(+st: M.State, +uid: String) -> Join:
  Ub.join.of(Ub.offer(st), uid, UB.Uber.bot(st))

def Join.err(j: Join) -> String:
  match j:
    case Join{e, _, _}:
      e

def Join.name(j: Join) -> String:
  match j:
    case Join{_, n, _}:
      n

def Join.look(j: Join) -> Nat:
  match j:
    case Join{_, _, l}:
      l

# the changes that tie a new replica bot (thread `th`) to `uid`
def Ub.joined(+st: M.State, +bot: String, +th: String, +name: String, +uid: String, +now: Nat) -> List<&2, M.Change>:
  M.UberSet{bot, uid, now} <> M.SettingSet{"uber.offer", "", now} <> Ub.ops.with(st, uid, now, [UO.Ub.b.bind(Ub.me(st), bot, th, name)])

# Where the uberbot lives
# -----------------------

# the replica's bot on a machine (its bind op), "" if unknown
def Ub.bound(+st: M.State, +machine: String) -> String:
  UO.Ub.field(UO.Ub.json(M.Setting.get(st, UO.Ub.key.reg(Ub.uid(st), "bind:" ++ machine), "")), "bot")

def Ub.bound.thread(+st: M.State, +machine: String) -> String:
  UO.Ub.field(UO.Ub.json(M.Setting.get(st, UO.Ub.key.reg(Ub.uid(st), "bind:" ++ machine), "")), "thread")

# the link a machine was reached over (set when its exchange first came
# in; "" before)
def Ub.link(+st: M.State, +machine: String) -> String:
  M.Setting.get(st, "uber.link." ++ Ub.uid(st) ++ "." ++ machine, "")

def Ub.far.id(+link: String, +id: String, +ok: Bool) -> String:
  Bool.pick(String, ok, FR.Fr.id(link, id), "")

def Ub.far.one(+st: M.State, +machine: String) -> String:
  Ub.far.id(Ub.link(st, machine), Ub.bound(st, machine), Bool.and(Bool.not(String.is_empty(Ub.link(st, machine))), Bool.not(String.is_empty(Ub.bound(st, machine)))))

def Ub.far.go(ms: List<&2, String>, +st: M.State) -> List<&2, String>:
  match ms:
    case Nil{}:
      Nil{}
    case +m <> t:
      BT.Post.keep(String, Bool.not(String.is_empty(Ub.far.one(st, m))), Ub.far.one(st, m), Ub.far.go(t, st))

# the bot ids on other machines that are this uberbot's replicas
# (`<link>~<bot>`), so a client does not list them as bots of their own
def Ub.far(+st: M.State) -> List<&2, String>:
  Ub.far.go(Ub.origins(st, Ub.uid(st)), st)

def Ub.far.is.go(xs: List<&2, String>, +id: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case +x <> t:
      Bool.or(String.eq(x, id), Ub.far.is.go(t, id))

def Ub.far.is(+st: M.State, +id: String) -> Bool:
  Bool.and(FR.Fr.is(id), Ub.far.is.go(Ub.far(st), id))

# the thread the uberbot's Chat tab shows: its own while this machine holds
# the conversation (or the holder is not known to be elsewhere), else the
# holder's, as the mirror here has it (`<link>~<thread>`)
def Ub.chat.k(here: Bool, +own: String, +far: String) -> String:
  Bool.pick(String, Bool.or(here, String.is_empty(far)), own, far)

def Ub.chat.far(+st: M.State, +holder: String) -> String:
  Bool.pick(String, Bool.or(String.is_empty(Ub.link(st, holder)), String.is_empty(Ub.bound.thread(st, holder))), "", FR.Fr.id(Ub.link(st, holder), Ub.bound.thread(st, holder)))

def Ub.chat(+st: M.State) -> String:
  Ub.chat.k(Ub.holder.me(st), BT.Bot.thread(BT.World.bot(M.State.bots(st), UB.Uber.bot(st))), Ub.chat.far(st, Ub.holder(st)))

# Talking to another machine
# --------------------------
# One request, uber.sync, over /far/rpc. Both ways carry the same body:
# {uid, machine, name, vv, ops, beat, offer}; the answer has the same
# shape (the caller's vv says which ops the answerer sends back).

def Ub.beat(+st: M.State) -> Bool:
  Bool.and(Ub.on(st), Ub.holder.me(st))

def Ub.offer.k(some: Bool, +b: BT.Bot, +uid: String) -> J.Json:
  match some:
    case True{}:
      J.Json.obj([J.KV{"uid", J.Str{uid}}, J.KV{"name", J.Str{BT.Bot.name(b)}}, J.KV{"look", J.Json.nat(BT.Bot.look(b))}])
    case False{}:
      J.Null{}

def Ub.offer.obj(+st: M.State) -> J.Json:
  Ub.offer.k(Bool.not(String.is_empty(UB.Uber.bot(st))), BT.World.bot(M.State.bots(st), UB.Uber.bot(st)), Ub.uid(st))

def Ub.lines.go(xs: List<&2, String>) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      J.Str{x} <> Ub.lines.go(t)

def Ub.lines(xs: List<&2, String>) -> J.Json:
  J.Json.arr(Ub.lines.go(xs))

# the object both sides send: what this machine is, has and lacks
def Ub.sync.obj(+st: M.State, +name: String, +vv: J.Json) -> J.Json:
  J.Json.obj([J.KV{"uid", J.Str{Ub.uid(st)}}, J.KV{"machine", J.Str{Ub.me(st)}}, J.KV{"name", J.Str{name}}, J.KV{"vv", Ub.vv(st)},
    J.KV{"ops", Ub.lines(Ub.lacking(st, vv))}, J.KV{"beat", J.Flag{Ub.beat(st)}}, J.KV{"offer", Ub.offer.obj(st)}])

# the request to a machine whose version vector was last `pvv` (JSON text,
# "" if never heard)
def Ub.sync.req(+st: M.State, +name: String, +pvv: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"m", J.Str{"uber.sync"}}, J.KV{"id", J.Num{"0"}}, J.KV{"p", Ub.sync.obj(st, name, UO.Ub.json(pvv))}]))

# the answer to a request's object
def Ub.sync.ans(+st: M.State, +name: String, +p: J.Json) -> String:
  J.Json.show(Ub.sync.obj(st, name, J.Json.get_obj(p, "vv")))

type SyncIn is Data:
  SyncIn{changes: List<&2, M.Change>, machine: String, same: Bool, beat: Bool, vv: String, more: Bool}

def SyncIn.changes(s: SyncIn) -> List<&2, M.Change>:
  match s:
    case SyncIn{c, _, _, _, _, _}:
      c

def SyncIn.machine(s: SyncIn) -> String:
  match s:
    case SyncIn{_, m, _, _, _, _}:
      m

def SyncIn.same(s: SyncIn) -> Bool:
  match s:
    case SyncIn{_, _, x, _, _, _}:
      x

def SyncIn.beat(s: SyncIn) -> Bool:
  match s:
    case SyncIn{_, _, _, x, _, _}:
      x

def SyncIn.vv(s: SyncIn) -> String:
  match s:
    case SyncIn{_, _, _, _, x, _}:
      x

# the exchange is not over: this machine still lacks ops the other has
def SyncIn.more(s: SyncIn) -> Bool:
  match s:
    case SyncIn{_, _, _, _, _, x}:
      x

def Ub.ops.of(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      J.Json.as_str(Some{x}, "") <> Ub.ops.of(t)

def Ub.set.if(same: Bool, +k: String, +v: String, +now: Nat) -> List<&2, M.Change>:
  Bool.pick(List<&2, M.Change>, same, Nil{}, [M.SettingSet{k, v, now}])

def Ub.offer.put(+st: M.State, +v: String, +now: Nat) -> List<&2, M.Change>:
  Ub.set.if(String.eq(M.Setting.get(st, "uber.offer", ""), v), "uber.offer", v, now)

def Ub.offer.keep.k(+of: J.Json, +st: M.State, +machine: String, +link: String, +now: Nat) -> List<&2, M.Change>:
  Bool.pick(List<&2, M.Change>, Bool.and(Bool.not(String.is_empty(UO.Ub.field(of, "uid"))), String.is_empty(UB.Uber.bot(st))),
    Ub.offer.put(st, J.Json.show(J.Json.obj([J.KV{"uid", J.Str{UO.Ub.field(of, "uid")}}, J.KV{"name", J.Str{UO.Ub.field(of, "name")}},
      J.KV{"look", J.Json.nat(UO.Ub.nat(of, "look"))}, J.KV{"machine", J.Str{machine}}, J.KV{"link", J.Str{link}}])), now), Nil{})

# the offer a machine with no uberbot keeps
def Ub.offer.keep(+st: M.State, +p: J.Json, +link: String, +now: Nat) -> List<&2, M.Change>:
  Ub.offer.keep.k(J.Json.get_obj(p, "offer"), st, UO.Ub.field(p, "machine"), link, now)

def Ub.take.same(+st: M.State, +p: J.Json, +link: String, +now: Nat) -> List<&2, M.Change>:
  List.concat(&2, M.Change, [Ub.commit(Ub.ops.of(J.Json.elems(J.Json.get_obj(p, "ops"))), st),
    Ub.set.if(String.eq(Ub.link(st, UO.Ub.field(p, "machine")), link), "uber.link." ++ Ub.uid(st) ++ "." ++ UO.Ub.field(p, "machine"), link, now),
    Ub.set.if(String.is_empty(M.Setting.get(st, "uber.offer", "")), "uber.offer", "", now)])

def Ub.take.k(same: Bool, +st: M.State, +p: J.Json, +link: String, +now: Nat) -> List<&2, M.Change>:
  match same:
    case True{}:
      Ub.take.same(st, p, link, now)
    case False{}:
      Ub.offer.keep(st, p, link, now)

# whether a machine's object is of this machine's uberbot
def Ub.same(+st: M.State, +p: J.Json) -> Bool:
  Bool.and(Ub.on(st), Bool.and(Bool.not(String.is_empty(UO.Ub.field(p, "uid"))), String.eq(UO.Ub.field(p, "uid"), Ub.uid(st))))

def Ub.lacks.go(os: List<&2, String>, +st: M.State, +vv: J.Json) -> Bool:
  match os:
    case Nil{}:
      False{}
    case +o <> t:
      Bool.or(Nat.is_gt(UO.Ub.nat(vv, o), Ub.vv.of(st, Ub.uid(st), o)), Ub.lacks.go(t, st, vv))

# whether the other machine has ops this one lacks (a full batch came)
def Ub.lacks(+st: M.State, +p: J.Json) -> Bool:
  Ub.lacks.go(Ub.origins(st, Ub.uid(st)), st, J.Json.get_obj(p, "vv"))

# what a machine's object (a request, or the answer to ours) does here: the
# changes to log, who sent it and whether it is of this uberbot, whether it
# held the conversation (beat), its version vector
def Ub.take(+st: M.State, +p: J.Json, +link: String, +now: Nat) -> SyncIn:
  SyncIn{Ub.take.k(Ub.same(st, p), st, p, link, now), UO.Ub.field(p, "machine"), Ub.same(st, p), Bool.and(Ub.same(st, p), J.Json.get_bool(p, "beat", False{})),
    J.Json.show(J.Json.get_obj(p, "vv")), Bool.and(Ub.same(st, p), Ub.lacks(st, p))}
