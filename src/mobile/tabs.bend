import Base
import ../core/json.bend as J
import ../core/model.bend as M
import ../core/client.bend as U
import ../core/botui.bend as B
import ../core/bot.bend as BT
import ../core/cron.bend as CR
import ../core/plane.bend as PL
import ./plane.bend as MPL
import ./screen.bend as S

# ios-snappy: tabs. The phones draw a tab bar (Home, Threads, Bots,
# Routines, Settings); this is what Bend gives the bar, cheaply, from what
# the list already computed (never the whole plane): the badges, and every
# bot's routines as rows. One hub's `tabs` object is
#   {home: {badge}, bots: {badge}, routines: {badge, rows}}
# and hubs.bend merges them over the paired hubs.

# rooms with something unread
def MTab.rooms.unread(rs: List<&2, B.RRow>, +u: U.Ui, acc: Nat) -> Nat:
  match rs:
    case Nil{}:
      acc
    case B.RRow{+id, _, _, _} <> t:
      MTab.rooms.unread(t, u, Nat.add(acc, Bool.pick(Nat, Nat.is_gt(U.Rooms.unread(u, id), 0n), 1n, 0n)))

def MTab.bot.name(m: Maybe<&2, BT.Bot>) -> String:
  match m:
    case Some{b}:
      BT.Bot.name(b)
    case None{}:
      ""

# a routine as a row of the Routines tab: kind "routine", the words of the
# plane's routine row (title, sub), the bot it belongs to, when it is next
# due (`at`, 0 for never or off), how long ago it last ran, and the tap
# (act, value, nav) the plane's routine row sends, which opens its bot's
# Routines tab. "state" is idle, or off when the routine is switched off.
def MTab.routine(r: BT.Routine, +u: U.Ui, +now: Nat) -> J.Json:
  match r:
    case BT.Routine{+id, +bot, +name, +cron, _, +on, +last, _, _}:
      J.Json.obj([J.KV{"kind", J.Json.str("routine")}, J.KV{"id", J.Json.str(id)}, J.KV{"act", J.Json.str("uber-bot")},
        J.KV{"value", J.Json.str(bot ++ "|routines")}, J.KV{"title", J.Json.str(name)}, J.KV{"sub", J.Json.str(CR.Cron.describe(cron))},
        J.KV{"bot", J.Json.str(MTab.bot.name(BT.World.find.id(BT.World.bot(M.State.bots(U.Ui.state(u)), bot))))},
        J.KV{"state", J.Json.str(Bool.pick(String, on, "idle", "off"))},
        J.KV{"at", J.Json.nat(Bool.pick(Nat, on, PL.Plane.routine.next(CR.Cron.parse(cron), now), 0n))},
        J.KV{"ago", J.Json.str(Bool.pick(String, Nat.is_eq(last, 0n), "", U.Time.ago(now, last)))},
        J.KV{"machine", J.Json.str(U.Ui.far.name(u, bot))}, J.KV{"away", J.Json.bool(U.Ui.far.away(u, bot))},
        J.KV{"nav", J.Json.str(MPL.MPlane.nav("routine", id, bot ++ "|routines", U.Ui.state(u)))}])

def MTab.routines(rs: List<&2, BT.Routine>, +u: U.Ui, +now: Nat) -> List<&2, J.Json>:
  match rs:
    case Nil{}:
      Nil{}
    case +r <> t:
      MTab.routine(r, u, now) <> MTab.routines(t, u, now)

def MTab.badge(+n: Nat) -> J.Json:
  J.Json.obj([J.KV{"badge", J.Json.nat(n)}])

# one hub's tabs: the need-you count of the list's own tally (Plane.tally,
# the sidebar's count), rooms with unread, every bot's routines
def MTab.json(+u: U.Ui, +ix: U.SIx, +rows: List<&2, U.SRow>) -> J.Json:
  J.Json.obj([J.KV{"home", MTab.badge(PL.PTally.need(PL.Plane.tally(u, ix, rows)))},
    J.KV{"bots", MTab.badge(MTab.rooms.unread(B.BU.rooms(u), u, 0n))},
    J.KV{"routines", J.Json.obj([J.KV{"badge", J.Json.nat(0n)},
      J.KV{"rows", J.Json.arr(MTab.routines(BT.World.routines.all(M.State.bots(U.Ui.state(u))), u, S.Mob.now(u)))}])}])
