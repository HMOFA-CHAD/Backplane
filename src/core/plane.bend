import Base
import ./model.bend as M
import ./bot.bend as BT
import ./far.bend as FR
import ./cron.bend as CR
import ./once.bend as O
import ./client.bend as U
import ./botui.bend as BU
import ./uber.bend as UB

# The status plane (docs/uber.md)
# -------------------------------
# What the uberbot's Status tab shows, one value for every client (the
# window, the web and the phones draw it): what waits on the person, what
# runs, the bots, the rooms with news, the routines and the rest of the
# day's threads, here and on the owner's other machines (their threads and
# bots are in the client's state as <link>~<id>, far.bend).
#
# A row says what a click sends (act, val: the usual client action), the
# machine it is on ("" for this one) and its state: approval, question,
# failed, working, queued, finished, idle or away for a thread; the mood
# for a bot; unread for a room; working or idle for a routine. `at` is the
# last activity (a routine's: when it is next due, 0 for never).

type PRow is Data:
  PRow{kind: String, id: String, act: String, val: String, title: String, sub: String, machine: String, state: String, at: Nat, away: Bool}

# a machine: here (answering), away, or syncing (nothing has come yet)
type PMach is Data:
  PMach{name: String, state: String}

type Plane is Data:
  Plane{need: List<&2, PRow>, run: List<&2, PRow>, bots: List<&2, PRow>, rooms: List<&2, PRow>, routines: List<&2, PRow>, idle: List<&2, PRow>, idle_n: Nat, machines: List<&2, PMach>}

def Plane.need(p: Plane) -> List<&2, PRow>:
  match p:
    case Plane{n, _, _, _, _, _, _, _}:
      n

def Plane.run(p: Plane) -> List<&2, PRow>:
  match p:
    case Plane{_, r, _, _, _, _, _, _}:
      r

def Plane.bots(p: Plane) -> List<&2, PRow>:
  match p:
    case Plane{_, _, b, _, _, _, _, _}:
      b

def Plane.rooms(p: Plane) -> List<&2, PRow>:
  match p:
    case Plane{_, _, _, r, _, _, _, _}:
      r

def Plane.routines(p: Plane) -> List<&2, PRow>:
  match p:
    case Plane{_, _, _, _, r, _, _, _}:
      r

def Plane.idle(p: Plane) -> List<&2, PRow>:
  match p:
    case Plane{_, _, _, _, _, i, _, _}:
      i

def Plane.idle_n(p: Plane) -> Nat:
  match p:
    case Plane{_, _, _, _, _, _, n, _}:
      n

def Plane.machines(p: Plane) -> List<&2, PMach>:
  match p:
    case Plane{_, _, _, _, _, _, _, m}:
      m

def PRow.id(r: PRow) -> String:
  match r:
    case PRow{_, i, _, _, _, _, _, _, _, _}:
      i

def PRow.state(r: PRow) -> String:
  match r:
    case PRow{_, _, _, _, _, _, _, s, _, _}:
      s

def PRow.at(r: PRow) -> Nat:
  match r:
    case PRow{_, _, _, _, _, _, _, _, a, _}:
      a

# the shown idle threads are those of the last day, at most this many
def Plane.idle.max() -> Nat:
  50n

def Plane.idle.age() -> Nat:
  86400n

# a routine counts as running for this long after it fires, while its bot works
def Plane.routine.window() -> Nat:
  900n

# Threads
# -------

def Plane.state(p: M.Phase) -> String:
  match p:
    case M.PhApproval{}:
      "approval"
    case M.PhInput{}:
      "question"
    case M.PhFailed{}:
      "failed"
    case M.PhWorking{}:
      "working"
    case M.PhMonitoring{_}:
      "working"
    case M.PhQueued{}:
      "queued"
    case M.PhComplete{}:
      "finished"
    case M.PhStopped{}:
      "idle"
    case M.PhIdle{}:
      "idle"

# how much a state waits on the person (0: not at all)
def Plane.rank(+s: String) -> Nat:
  Bool.pick(Nat, String.eq(s, "approval"), 8n, Bool.pick(Nat, String.eq(s, "question"), 7n, Bool.pick(Nat, String.eq(s, "failed"), 6n, 0n)))

# the section a state goes to: 0 need, 1 run, 2 the rest
def Plane.sec(+s: String) -> Nat:
  Bool.pick(Nat, Nat.is_gt(Plane.rank(s), 0n), 0n, Bool.pick(Nat, Bool.or(String.eq(s, "working"), String.eq(s, "queued")), 1n, 2n))

# a thread of a machine that does not answer is not asking for anything
# A thread whose open asks are all questions or plans is asking, though the
# hub counts every ask as pending (the phase then says approval): the clients
# draw a question apart from an approval.
def Plane.asking(+s: String, +ix: U.SIx, +id: String) -> String:
  Bool.pick(String, Bool.and(String.eq(s, "approval"), Bool.and(Bool.not(U.Asks.kind(U.SIx.open(ix, id), "approval")),
    Bool.or(U.Asks.kind(U.SIx.open(ix, id), "input"), U.Asks.kind(U.SIx.open(ix, id), "plan")))), "question", s)

def Plane.thread.k(+away: Bool, +id: String, +title: String, +sub: String, +machine: String, +phase: String, +at: Nat) -> PRow:
  PRow{"thread", id, "select", id, title, sub, machine, Bool.pick(String, away, "away", phase), at, away}

def Plane.thread.t(+t: M.Thread, +at: Nat, +pt: String, +u: U.Ui, +ix: U.SIx, +st: M.State) -> PRow:
  Plane.thread.k(U.Ui.far.away(u, M.Thread.id(t)), M.Thread.id(t), U.Active.title(t), pt, U.Ui.far.name(u, M.Thread.id(t)), Plane.asking(Plane.state(U.Side.phase.ix(ix, st, t)), ix, M.Thread.id(t)), at)

def Plane.thread(r: U.ARow, +u: U.Ui, +ix: U.SIx, +st: M.State) -> PRow:
  match r:
    case U.ARow{_, +at, +t, _, +pt, _}:
      Plane.thread.t(t, at, pt, u, ix, st)

def Plane.keep(drop: Bool, x: PRow, rest: List<&2, PRow>) -> List<&2, PRow>:
  match drop:
    case True{}:
      rest
    case False{}:
      x <> rest

# the live threads of every project (settled ones, faded, are left out)
def Plane.threads(rs: List<&2, U.ARow>, +u: U.Ui, +ix: U.SIx, +st: M.State) -> List<&2, PRow>:
  match rs:
    case Nil{}:
      Nil{}
    case +r <> t:
      Plane.keep(U.ARow.faded(r), Plane.thread(r, u, ix, st), Plane.threads(t, u, ix, st))

# A bot's own thread waits on the person or runs like any other; it shows
# in those sections as the bot (the uberbot's opens its tab)
def Plane.bot.k(+away: Bool, +id: String, +name: String, +machine: String, +phase: String, +at: Nat, +uber: Bool) -> PRow:
  PRow{"bot", id, Bool.pick(String, uber, "uber", "bot"), Bool.pick(String, uber, "", id), name, "", machine, Bool.pick(String, away, "away", phase), at, away}

def Plane.bot.t(+b: BT.Bot, +th: String, +u: U.Ui, +ix: U.SIx, +st: M.State) -> PRow:
  Plane.bot.k(U.Ui.far.away(u, BT.Bot.id(b)), BT.Bot.id(b), BT.Bot.name(b), U.Ui.far.name(u, BT.Bot.id(b)), Plane.asking(Plane.state(U.Side.phase.ix(ix, st, U.Ui.thread(st, th))), ix, th),
    U.Active.activity(U.Ui.thread(st, th)), UB.Uber.is(st, BT.Bot.id(b)))

# only a bot that has a thread, and one that is not at rest, shows here
def Plane.bots.r(+row: PRow, rest: List<&2, PRow>) -> List<&2, PRow>:
  Plane.keep(Nat.is_gt(Plane.sec(PRow.state(row)), 1n), row, rest)

def Plane.bots.k(none: Bool, +b: BT.Bot, +u: U.Ui, +ix: U.SIx, +st: M.State, rest: List<&2, PRow>) -> List<&2, PRow>:
  match none:
    case True{}:
      rest
    case False{}:
      Plane.bots.r(Plane.bot.t(b, BT.Bot.thread(b), u, ix, st), rest)

def Plane.bots.go(bs: List<&2, BT.Bot>, +u: U.Ui, +ix: U.SIx, +st: M.State) -> List<&2, PRow>:
  match bs:
    case Nil{}:
      Nil{}
    case +b <> t:
      Plane.bots.k(String.is_empty(BT.Bot.thread(b)), b, u, ix, st, Plane.bots.go(t, u, ix, st))

# Ordering
# --------

# most urgent first, the newer first among equals (law plane_need_ranked)
def Plane.before(a: PRow, b: PRow) -> Bool:
  match a b:
    case PRow{_, _, _, _, _, _, _, +sa, +aa, _} PRow{_, _, _, _, _, _, _, +sb, +ab, _}:
      Bool.pick(Bool, Nat.is_eq(Plane.rank(sa), Plane.rank(sb)), Nat.is_ge(aa, ab), Nat.is_gt(Plane.rank(sa), Plane.rank(sb)))

def Plane.newer(a: PRow, b: PRow) -> Bool:
  Nat.is_ge(PRow.at(a), PRow.at(b))

def Plane.due.le(+a: Nat, +b: Nat) -> Bool:
  Bool.pick(Bool, Nat.is_eq(a, 0n), Nat.is_eq(b, 0n), Bool.or(Nat.is_eq(b, 0n), Nat.is_le(a, b)))

# a routine running first, then the soonest due (never, 0, last)
def Plane.due.before(a: PRow, b: PRow) -> Bool:
  match a b:
    case PRow{_, _, _, _, _, _, _, +sa, +aa, _} PRow{_, _, _, _, _, _, _, +sb, +ab, _}:
      Bool.pick(Bool, String.eq(sa, sb), Plane.due.le(aa, ab), String.eq(sa, "working"))

# the rows of a section (see Plane.sec), in the order they were given
def Plane.part(rs: List<&2, PRow>, +n: Nat) -> List<&2, PRow>:
  match rs:
    case Nil{}:
      Nil{}
    case +r <> t:
      Plane.keep(Bool.not(Nat.is_eq(Plane.sec(PRow.state(r)), n)), r, Plane.part(t, n))

# the threads (not bots) active in the last day
def Plane.recent(rs: List<&2, PRow>, +now: Nat) -> List<&2, PRow>:
  match rs:
    case Nil{}:
      Nil{}
    case +r <> t:
      Plane.keep(Bool.not(Nat.is_le(now, Nat.add(PRow.at(r), Plane.idle.age()))), r, Plane.recent(t, now))

# every thread row once, keyed by what it stands for
def Plane.ky(+r: PRow) -> O.Ky<PRow>:
  O.Ky{"t:" ++ PRow.id(r), r}

def Plane.kys(rs: List<&2, PRow>) -> List<&2, O.Ky<PRow>>:
  match rs:
    case Nil{}:
      Nil{}
    case +r <> t:
      Plane.ky(r) <> Plane.kys(t)

def Plane.bky(+r: PRow) -> O.Ky<PRow>:
  O.Ky{"b:" ++ PRow.id(r), r}

def Plane.bkys(rs: List<&2, PRow>) -> List<&2, O.Ky<PRow>>:
  match rs:
    case Nil{}:
      Nil{}
    case +r <> t:
      Plane.bky(r) <> Plane.bkys(t)

# the thread rows and the bots' own, before each is kept once
def Plane.all.src(+u: U.Ui, +ix: U.SIx, +now: Nat) -> List<&2, O.Ky<PRow>>:
  List.append(&2, O.Ky<PRow>, Plane.kys(Plane.threads(U.Active.rows.ix(U.Ui.state(u), ix, now, ""), u, ix, U.Ui.state(u))),
    Plane.bkys(Plane.bots.go(BT.World.bots(M.State.bots(U.Ui.state(u))), u, ix, U.Ui.state(u))))

# ... and kept once (law plane_each_once)
def Plane.all.keyed(+u: U.Ui, +ix: U.SIx, +now: Nat) -> List<&2, O.Ky<PRow>>:
  O.Once.of(PRow, Plane.all.src(u, ix, now))

# Bots
# ----

def Plane.bot.row(r: BU.BRow, +st: M.State) -> PRow:
  match r:
    case BU.BRow{+i, +n, +th, _, +mood, +note, _, _, +pe, _}:
      PRow{"bot", i, BU.BU.act(BU.BRow{i, n, th, 0n, mood, note, False{}, False{}, pe, ""}), i, n, Bool.pick(String, BU.Mood.moving(mood), note, ""), pe, mood,
        U.Active.activity(U.Ui.thread(st, th)), String.eq(mood, "away")}

def Plane.bot.rows(rs: List<&2, BU.BRow>, +st: M.State) -> List<&2, PRow>:
  match rs:
    case Nil{}:
      Nil{}
    case +r <> t:
      Plane.bot.row(r, st) <> Plane.bot.rows(t, st)

# Rooms
# -----

def Plane.room.last(ps: List<&2, BT.Post>) -> Nat:
  match ps:
    case BT.Post{_, _, _, _, _, +at} <> _:
      at
    case Nil{}:
      0n

def Plane.room.k(n: Nat, +id: String, +name: String, +at: Nat, rest: List<&2, PRow>) -> List<&2, PRow>:
  match n:
    case 0n:
      rest
    case 1n+k:
      PRow{"room", id, "room", id, name, Nat.show(1n+k) ++ " unread", "", "unread", at, False{}} <> rest

def Plane.rooms.go(rs: List<&2, BT.Room>, +u: U.Ui) -> List<&2, PRow>:
  match rs:
    case Nil{}:
      Nil{}
    case +r <> t:
      Plane.room.k(U.Rooms.unread(u, BT.Room.id(r)), BT.Room.id(r), BT.Room.name(r), Plane.room.last(BT.World.posts(M.State.bots(U.Ui.state(u)), BT.Room.id(r), 1n)), Plane.rooms.go(t, u))

# Routines
# --------

def Plane.routine.next(m: Maybe<&2, CR.Cron>, +now: Nat) -> Nat:
  match m:
    case Some{c}:
      CR.Cron.next(c, now, 0n, True{})
    case None{}:
      0n

# a busy bot's routine that fired within the window is running
def Plane.routine.run(busy: Bool, +last: Nat, +now: Nat) -> Bool:
  Bool.and(Bool.and(busy, Nat.is_gt(last, 0n)), Nat.is_le(now, Nat.add(last, Plane.routine.window())))

def Plane.routine.k(on: Bool, run: Bool, +id: String, +bot: String, +name: String, +cron: String, +machine: String, +next: Nat, away: Bool, rest: List<&2, PRow>) -> List<&2, PRow>:
  match on:
    case True{}:
      PRow{"routine", id, "uber-bot", bot ++ "|routines", name, CR.Cron.describe(cron), machine, Bool.pick(String, run, "working", "idle"), next, away} <> rest
    case False{}:
      rest

def Plane.routine.t(r: BT.Routine, +u: U.Ui, +ix: U.SIx, +now: Nat, rest: List<&2, PRow>) -> List<&2, PRow>:
  match r:
    case BT.Routine{+id, +bot, +name, +cron, _, on, +last, _, _}:
      Plane.routine.k(on, Plane.routine.run(Nat.is_gt(Plane.sec(Plane.state(U.Side.phase.ix(ix, U.Ui.state(u), U.Ui.thread(U.Ui.state(u), BT.Bot.thread(BT.World.bot(M.State.bots(U.Ui.state(u)), bot)))))), 0n), last, now),
        id, bot, name, cron, U.Ui.far.name(u, bot), Plane.routine.next(CR.Cron.parse(cron), now), U.Ui.far.away(u, bot), rest)

def Plane.routines.go(rs: List<&2, BT.Routine>, +u: U.Ui, +ix: U.SIx, +now: Nat) -> List<&2, PRow>:
  match rs:
    case Nil{}:
      Nil{}
    case +r <> t:
      Plane.routine.t(r, u, ix, now, Plane.routines.go(t, u, ix, now))

# Machines
# --------

def Plane.mach.state(away: Bool, +head: Nat) -> String:
  Bool.pick(String, away, "away", Bool.pick(String, Nat.is_eq(head, 0n), "syncing", "here"))

def Plane.mach.name(+u: U.Ui, +id: String, +fallback: String) -> String:
  Bool.pick(String, String.is_empty(U.Ui.info(u, "far.name." ++ id)), fallback, U.Ui.info(u, "far.name." ++ id))

def Plane.machs(ps: List<&2, BT.Peer>, +u: U.Ui) -> List<&2, PMach>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      PMach{Plane.mach.name(u, BT.Peer.id(p), BT.Peer.name(p)), Plane.mach.state(String.eq(U.Ui.info(u, "far.away." ++ BT.Peer.id(p)), "1"), FR.Fr.head(U.Ui.state(u), BT.Peer.id(p)))} <> Plane.machs(t, u)

def Plane.machine.names(rs: List<&2, U.MRow>) -> List<&2, String>:
  match rs:
    case Nil{}:
      Nil{}
    case U.MRow{+n, _, _} <> t:
      n <> Plane.machine.names(t)

def Plane.machines.of(+u: U.Ui) -> List<&2, PMach>:
  PMach{Maybe.default(&2, String, List.head(&2, String, Plane.machine.names(U.Machines.rows(u))), "This machine"), "here"} <> Plane.machs(BU.BU.peers.of(u), u)

# The plane
# ---------

def Plane.sort(rs: List<&2, PRow>) -> List<&2, PRow>:
  List.sort(~PRow, ~Plane.before, rs)

def Plane.of.i(+idle: List<&2, PRow>, +all: List<&2, PRow>, +u: U.Ui, +ix: U.SIx, +now: Nat) -> Plane:
  Plane{Plane.sort(Plane.part(all, 0n)), List.sort(~PRow, ~Plane.newer, Plane.part(all, 1n)),
    Plane.bot.rows(BU.BU.rows(u), U.Ui.state(u)),
    List.sort(~PRow, ~Plane.newer, Plane.rooms.go(BT.World.rooms(M.State.bots(U.Ui.state(u))), u)),
    List.sort(~PRow, ~Plane.due.before, Plane.routines.go(BT.World.routines.all(M.State.bots(U.Ui.state(u))), u, ix, now)),
    List.take(&2, PRow, idle, Plane.idle.max()), List.length(&2, PRow, idle), Plane.machines.of(u)}

def Plane.of.k(+all: List<&2, PRow>, +u: U.Ui, +ix: U.SIx, +now: Nat) -> Plane:
  Plane.of.i(Plane.sort(Plane.recent(Plane.part(all, 2n), now)), all, u, ix, now)

# A thread row is made only for a thread that shows: one that waits on the
# person or runs, or (when idle threads are wanted) one active in the last
# day. The rest are told apart by their state alone, which is cheap; a row's
# machine, title and project cost more, and a phone with 300 threads spent
# its time on the ones nobody sees.
def Plane.thread.t.s(r: U.ARow, +state: String, +u: U.Ui, +st: M.State) -> PRow:
  match r:
    case U.ARow{_, +at, +t, _, +pt, _}:
      Plane.thread.k(U.Ui.far.away(u, M.Thread.id(t)), M.Thread.id(t), U.Active.title(t), pt, U.Ui.far.name(u, M.Thread.id(t)), state, at)

def Plane.thread.st(r: U.ARow, +ix: U.SIx, +st: M.State) -> String:
  match r:
    case U.ARow{_, _, +t, _, _, _}:
      Plane.asking(Plane.state(U.Side.phase.ix(ix, st, t)), ix, M.Thread.id(t))

def Plane.arow.at(r: U.ARow) -> Nat:
  match r:
    case U.ARow{_, +at, _, _, _, _}:
      at

def Plane.shows(+state: String, +at: Nat, +now: Nat, +idle: Bool) -> Bool:
  Bool.or(Nat.is_lt(Plane.sec(state), 2n), Bool.and(idle, Bool.not(Nat.is_le(now, Nat.add(at, Plane.idle.age())))))

def Plane.threads.m(show: Bool, r: U.ARow, +state: String, +u: U.Ui, +st: M.State, rest: List<&2, PRow>) -> List<&2, PRow>:
  match show:
    case True{}:
      Plane.thread.t.s(r, state, u, st) <> rest
    case False{}:
      rest

def Plane.threads.k(+r: U.ARow, +state: String, +u: U.Ui, +ix: U.SIx, +st: M.State, +idle: Bool, +now: Nat, rest: List<&2, PRow>) -> List<&2, PRow>:
  Plane.threads.m(Bool.and(Bool.not(U.ARow.faded(r)), Plane.shows(state, Plane.arow.at(r), now, idle)), r, state, u, st, rest)

def Plane.threads.f(rs: List<&2, U.ARow>, +u: U.Ui, +ix: U.SIx, +st: M.State, +idle: Bool, +now: Nat) -> List<&2, PRow>:
  match rs:
    case Nil{}:
      Nil{}
    case +r <> t:
      Plane.threads.k(r, Plane.thread.st(r, ix, st), u, ix, st, idle, now, Plane.threads.f(t, u, ix, st, idle, now))

def Plane.all.vals(+u: U.Ui, +ix: U.SIx, +now: Nat, +idle: Bool) -> List<&2, PRow>:
  List.append(&2, PRow, Plane.threads.f(U.Active.rows.ix(U.Ui.state(u), ix, now, ""), u, ix, U.Ui.state(u), idle, now),
    Plane.bots.go(BT.World.bots(M.State.bots(U.Ui.state(u))), u, ix, U.Ui.state(u)))

# the idle threads, only when they are wanted (the Status tab shows them)
def Plane.idle.of(want: Bool, +all: List<&2, PRow>, +now: Nat) -> List<&2, PRow>:
  match want:
    case True{}:
      Plane.sort(Plane.recent(Plane.part(all, 2n), now))
    case False{}:
      Nil{}

def Plane.of.f.k(+all: List<&2, PRow>, +u: U.Ui, +ix: U.SIx, +now: Nat, +idle: Bool) -> Plane:
  Plane.of.i(Plane.idle.of(idle, all, now), all, u, ix, now)

# the same plane without the keyed pass (the phones' screens); with no idle
# threads unless they are wanted (idle_n is then 0)
def Plane.of.f(+u: U.Ui, +ix: U.SIx, +now: Nat, +idle: Bool) -> Plane:
  Plane.of.f.k(Plane.all.vals(u, ix, now, idle), u, ix, now, idle)

def Plane.of.x(+u: U.Ui, +ix: U.SIx, +now: Nat) -> Plane:
  Plane.of.k(O.Once.vals(PRow, Plane.all.keyed(u, ix, now)), u, ix, now)

# the status plane as of `now` (the sidebar's index built once)
def Plane.of(+u: U.Ui, +now: Nat) -> Plane:
  Plane.of.x(u, U.Side.ix(U.Ui.state(u)), now)

# Cheap to compute, and different whenever the plane can be: the log's
# sequence, each machine's head and whether it answers, and the minute
def Plane.key.peers(ps: List<&2, BT.Peer>, +u: U.Ui) -> String:
  match ps:
    case Nil{}:
      ""
    case +p <> t:
      BT.Peer.id(p) ++ ":" ++ Nat.show(FR.Fr.head(U.Ui.state(u), BT.Peer.id(p))) ++ ":" ++ U.Ui.info(u, "far.away." ++ BT.Peer.id(p)) ++ ";" ++ Plane.key.peers(t, u)

def Plane.key(+u: U.Ui, +now: Nat) -> String:
  Nat.show(U.Ui.seq(u)) ++ "|" ++ Nat.show(Nat.div(now, 60n)) ++ "|" ++ Plane.key.peers(BU.BU.peers.of(u), u)

# the bots at work now (their mood: working or talking), for the strip
def Plane.working.k(hit: Bool, +n: Nat) -> Nat:
  match hit:
    case True{}:
      1n+n
    case False{}:
      n

def Plane.working.go(rs: List<&2, PRow>) -> Nat:
  match rs:
    case Nil{}:
      0n
    case +r <> t:
      Plane.working.k(Bool.or(String.eq(PRow.state(r), "work"), String.eq(PRow.state(r), "talk")), Plane.working.go(t))

def Plane.working(+p: Plane) -> Nat:
  Plane.working.go(Plane.bots(p))

# the sidebar row's words: "3 need you · 7 running" ("" when neither)
def Plane.counts.part(+n: Nat, +words: String) -> String:
  Bool.pick(String, Nat.is_eq(n, 0n), "", Nat.show(n) ++ " " ++ words)

def Plane.counts.join(+a: String, +b: String) -> String:
  Bool.pick(String, String.is_empty(a), b, Bool.pick(String, String.is_empty(b), a, a ++ " · " ++ b))

def Plane.counts(+p: Plane) -> String:
  Plane.counts.join(Plane.counts.part(List.length(&2, PRow, Plane.need(p)), "need you"), Plane.counts.part(List.length(&2, PRow, Plane.run(p)), "running"))

# ids in the three thread sections, for law plane_each_once
def Plane.ids(rs: List<&2, PRow>) -> List<&2, String>:
  match rs:
    case Nil{}:
      Nil{}
    case PRow{k, +i, _, _, _, _, _, _, _, _} <> t:
      i <> Plane.ids(t)

# what a click on the first row sends ("act val"), for law plane_hit_opens
def Plane.act.of(rs: List<&2, PRow>) -> String:
  match rs:
    case PRow{_, _, +a, +v, _, _, _, _, _, _} <> _:
      a ++ " " ++ v
    case Nil{}:
      ""

# the machine of the second row in a section (for tests)
def Plane.machine.of(rs: List<&2, PRow>) -> String:
  match rs:
    case _ <> PRow{_, _, _, _, _, _, +m, _, _, _} <> _:
      m
    case _:
      ""

# need, run and the rest are each in urgency order: no row waits on the
# person less than the one after it (law plane_need_ranked)
def Plane.ranked.head(a: PRow, t: List<&2, PRow>) -> Bool:
  match t:
    case Nil{}:
      True{}
    case +b <> _:
      Nat.is_ge(Plane.rank(PRow.state(a)), Plane.rank(PRow.state(b)))

def Plane.ranked(rs: List<&2, PRow>) -> Bool:
  match rs:
    case Nil{}:
      True{}
    case +a <> +t:
      Bool.and(Plane.ranked.head(a, t), Plane.ranked(t))

# what a click on a thread's row sends, "action value" (law plane_hit_opens)
def Plane.hit(r: PRow) -> String:
  match r:
    case PRow{_, _, +a, +v, _, _, _, _, _, _}:
      a ++ " " ++ v

# every thread id in need, run and idle
def Plane.threads.ids(+p: Plane) -> List<&2, String>:
  List.append(&2, String, Plane.ids(Plane.need(p)), List.append(&2, String, Plane.ids(Plane.run(p)), Plane.ids(Plane.idle(p))))

# a client for the laws: threads in every state, a bot at work, a room, a routine
def Plane.demo() -> U.Ui:
  U.Ui.far.st(U.Ui.init(200000n), M.State.replay([M.ProjectCreated{"p1", "One", "/a", 1n},
    M.ThreadCreated{"t1", "p1", "A", M.Local{}, "", "", "claude", "", 199000n}, M.TurnChanged{"t1", M.Running{}, 199001n}, M.AskOpened{"a1", "t1", "approval", "Bash", "ls", "", 199002n},
    M.ThreadCreated{"t2", "p1", "B", M.Local{}, "", "", "claude", "", 199100n}, M.AskOpened{"a2", "t2", "input", "", "?", "", 199101n},
    M.ThreadCreated{"t3", "p1", "C", M.Local{}, "", "", "claude", "", 199200n}, M.TurnChanged{"t3", M.Failed{}, 199201n},
    M.ThreadCreated{"t4", "p1", "D", M.Local{}, "", "", "claude", "", 199300n}, M.TurnChanged{"t4", M.Running{}, 199301n},
    M.ThreadCreated{"t6", "p1", "F", M.Local{}, "", "", "claude", "", 199500n}, M.TurnChanged{"t6", M.Completed{}, 199501n},
    M.ThreadCreated{"bt1", "", "Kit", M.Local{}, "", "", "claude", "", 100n}, M.BotSet{"b1", "Kit", "bt1", 7n, "", 100n}, M.TurnChanged{"bt1", M.Running{}, 199900n},
    M.RoomSet{"r1", "ops", "b1", 150n}, M.RoomPosted{"m1", "r1", "b1", "hello", 0n, 199800n},
    M.RoutineSet{"rt1", "b1", "Digest", "0 9 * * *", "sum up", True{}, 160n}], M.State.empty()))
