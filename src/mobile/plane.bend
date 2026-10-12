import Base
import ../core/json.bend as J
import ../core/model.bend as M
import ../core/client.bend as U
import ../core/botui.bend as B
import ../core/plane.bend as PL
import ./bots.bend as MB

# The status plane on the phones (docs/uber.md): the uberbot's card and
# the plane under it as JSON, built from core's Plane once a screen and
# only while a bot is the uberbot. The apps draw it (Plane.swift,
# Plane.kt) and send each row's act and value back; "id" and "value" are
# the keys hubs.bend qualifies with the hub, so a merged row is routed to
# the hub it came from.

# a row of the plane: what it is (kind: thread, bot, room, routine), what a
# tap sends (act, value), its words (title, sub), its state (thread: approval,
# question, failed, working, queued, finished, idle, away; bot: its mood;
# room: unread; routine: working, idle), how long ago, and the machine
# when it is not this one ("machine" is left out for this one)
def MPlane.machine(+m: String) -> List<&2, J.KV>:
  Bool.pick(List<&2, J.KV>, String.is_empty(m), Nil{}, [J.KV{"machine", J.Json.str(m)}])

# a routine's `at` is when it is next due, so it has no age
def MPlane.ago(+kind: String, +now: Nat, +at: Nat) -> String:
  MB.MBots.ago(Bool.or(String.eq(kind, "routine"), Nat.is_eq(at, 0n)), now, at)

# the uberbot's own row has no value; its id routes the tap to its hub
def MPlane.value(+act: String, +val: String, +id: String) -> String:
  Bool.pick(String, Bool.and(String.eq(act, "uber"), String.is_empty(val)), id, val)

def MPlane.row(r: PL.PRow, +now: Nat) -> J.Json:
  match r:
    case PL.PRow{+kind, +id, +act, +val, +title, +sub, +machine, +state, +at, +away}:
      J.Json.obj(List.append(&2, J.KV,
        [J.KV{"kind", J.Json.str(kind)}, J.KV{"id", J.Json.str(id)}, J.KV{"act", J.Json.str(act)}, J.KV{"value", J.Json.str(MPlane.value(act, val, id))},
         J.KV{"title", J.Json.str(title)}, J.KV{"sub", J.Json.str(sub)}, J.KV{"state", J.Json.str(state)},
         J.KV{"ago", J.Json.str(MPlane.ago(kind, now, at))}, J.KV{"at", J.Json.nat(at)}, J.KV{"away", J.Json.bool(away)}],
        MPlane.machine(machine)))

def MPlane.rows(rs: List<&2, PL.PRow>, +now: Nat) -> List<&2, J.Json>:
  match rs:
    case Nil{}:
      Nil{}
    case +r <> t:
      MPlane.row(r, now) <> MPlane.rows(t, now)

def MPlane.mach(ms: List<&2, PL.PMach>) -> List<&2, J.Json>:
  match ms:
    case Nil{}:
      Nil{}
    case PL.PMach{+n, +s} <> t:
      J.Json.obj([J.KV{"name", J.Json.str(n)}, J.KV{"state", J.Json.str(s)}]) <> MPlane.mach(t)

def MPlane.json(+p: PL.Plane, +now: Nat) -> J.Json:
  J.Json.obj([J.KV{"need", J.Json.arr(MPlane.rows(PL.Plane.need(p), now))}, J.KV{"run", J.Json.arr(MPlane.rows(PL.Plane.run(p), now))},
    J.KV{"idle", J.Json.arr(MPlane.rows(PL.Plane.idle(p), now))}, J.KV{"idleN", J.Json.nat(PL.Plane.idle_n(p))},
    J.KV{"working", J.Json.nat(PL.Plane.working(p))}, J.KV{"bots", J.Json.arr(MPlane.rows(PL.Plane.bots(p), now))}, J.KV{"rooms", J.Json.arr(MPlane.rows(PL.Plane.rooms(p), now))},
    J.KV{"routines", J.Json.arr(MPlane.rows(PL.Plane.routines(p), now))}, J.KV{"machines", J.Json.arr(MPlane.mach(PL.Plane.machines(p)))}])

# the uberbot's card: a bot's row (MBots.row) with the plane's counts
def MPlane.card.k(j: J.Json, +counts: String) -> J.Json:
  match j:
    case J.Obj{fs}:
      J.Obj{J.Field{"counts", J.Str{counts}, fs}}
    case x:
      x

def MPlane.card(r: B.BRow, +p: PL.Plane) -> J.Json:
  MPlane.card.k(MB.MBots.row(r), PL.Plane.counts(p))

type MUber is Data:
  MUber{uber: J.Json, plane: J.Json}

def MUber.uber(m: MUber) -> J.Json:
  match m:
    case MUber{u, _}:
      u

def MUber.plane(m: MUber) -> J.Json:
  match m:
    case MUber{_, p}:
      p

def MPlane.of.k(r: B.BRow, +p: PL.Plane, +now: Nat) -> MUber:
  MUber{MPlane.card(r, p), MPlane.json(p, now)}

# neither while no bot is the uberbot
def MPlane.of(m: Maybe<&2, B.BRow>, +u: U.Ui, +ix: U.SIx, +now: Nat) -> MUber:
  match m:
    case Some{r}:
      MPlane.of.k(r, PL.Plane.of.x(u, ix, now), now)
    case None{}:
      MUber{J.Null{}, J.Null{}}
