import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/codec.bend as K
import ../src/core/json.bend as J
import ../src/core/bot.bend as BT
import ../src/core/ubop.bend as UO
import ../src/core/uber.bend as UB
import ../src/core/ubersync.bend as US
import ../src/core/hub.bend as B
import ../src/core/bothub.bend as BH
import ../src/core/xref.bend as UX

# One uberbot on several machines: stamps, registers, merge, lease, fires,
# derive (laws uber_merge_*, uber_forget_*, uber_*_term, uber_fire_*,
# uber_slot_once, uber_pinned_stays, uber_derived_no_ops).

def yes(b: Bool) -> String:
  Bool.pick(String, b, "yes", "no")

def mk(+me: String, +bot: String, +th: String, +name: String) -> List<&2, M.Change>:
  [M.ThreadCreated{th, "", name, M.Local{}, "", "", "claude", "", 100n}, M.BotSet{bot, name, th, 7n, "", 100n}, M.SettingSet{"machine.id", me, 100n},
    M.UberSet{bot, "u1-x", 101n}]

def sa(+extra: List<&2, M.Change>) -> M.State:
  M.State.replay(List.append(&2, M.Change, mk("mA", "b1", "t1", "Kit"), extra), M.State.empty())

def sb(+extra: List<&2, M.Change>) -> M.State:
  M.State.replay(List.append(&2, M.Change, mk("mB", "b2", "t2", "Kit"), extra), M.State.empty())

def op(+origin: String, +n: Nat, +secs: Nat, +ctr: Nat, +body: String) -> M.Change:
  M.UberOp{"u1-x", origin, n, UO.Ub.stamp.make(secs, ctr, origin), body, secs}

def g(+st: M.State, +k: String) -> String:
  M.Setting.get(st, k, "-")

# the registers and counts a state ends with
def dig(+st: M.State) -> String:
  g(st, "uber.r.u1-x.mem:color") ++ "|" ++ g(st, "uber.rs.u1-x.mem:color") ++ "|" ++ g(st, "uber.r.u1-x.space") ++ "|" ++ g(st, "uber.r.u1-x.lease") ++ "|" ++
    g(st, "uber.vv.u1-x.mA") ++ "|" ++ g(st, "uber.vv.u1-x.mB") ++ "|" ++ g(st, "uber.fired.u1-x.mA:r1") ++ "|" ++ g(st, "uber.origins.u1-x")

def tags(cs: List<&2, M.Change>) -> String:
  match cs:
    case Nil{}:
      ""
    case c <> t:
      J.Json.get_str(K.Change.encode(c), "$", "") ++ ";" ++ tags(t)

def lines(cs: List<&2, M.Change>) -> List<&2, String>:
  match cs:
    case Nil{}:
      Nil{}
    case M.UberOp{u, o, n, s, p, a} <> t:
      UO.Ub.line(u, o, n, s, p, a) <> lines(t)
    case _ <> t:
      lines(t)

def n(l: List<&2, String>) -> String:
  Nat.show(List.length(&2, String, l))

def first(cs: List<&2, M.Change>) -> String:
  match cs:
    case Nil{}:
      "none"
    case c <> t:
      J.Json.show(K.Change.encode(c))

def count(xs: List<&2, String>) -> Nat:
  List.length(&2, String, xs)

def main() -> IO(Unit):
  do IO<Unit>:
    +blue : M.Change = op("mA", 1n, 1000n, 0n, UO.Ub.b.mem("color", "fact", "blue", ""))
    +red : M.Change = op("mB", 1n, 1001n, 0n, UO.Ub.b.mem("color", "fact", "red", ""))
    +gone : M.Change = op("mA", 2n, 1002n, 0n, UO.Ub.b.forget("color"))
    +sp : M.Change = op("mB", 2n, 1003n, 0n, UO.Ub.b.space("{}"))
    C.Check.str("stamp make", UO.Ub.stamp.make(5n, 3n, "mA"), "0000000005.000003.mA")
    C.Check.str("stamp next later clock", UO.Ub.stamp.next("0000000005.000003.mA", 9n, "mB"), "0000000009.000000.mB")
    C.Check.str("stamp next same second", UO.Ub.stamp.next("0000000009.000000.mA", 9n, "mB"), "0000000009.000001.mB")
    C.Check.str("stamp next behind the clock", UO.Ub.stamp.next("0000000020.000004.mA", 9n, "mB"), "0000000020.000005.mB")
    C.Check.str("stamp order", yes(UO.Ub.stamp.gt("0000000009.000001.mA", "0000000009.000000.mB")), "yes")
    C.Check.str("origin breaks a tie", yes(UO.Ub.stamp.gt("0000000009.000000.mB", "0000000009.000000.mA")), "yes")
    C.Check.str("the later stamp wins the register", dig(sa([blue, red])), dig(sa([red, blue])))
    C.Check.str("red is the later", g(sa([blue, red]), "uber.r.u1-x.mem:color"), UO.Ub.b.mem("color", "fact", "red", ""))
    C.Check.str("an op twice is once", dig(sa([blue, blue])), dig(sa([blue])))
    C.Check.str("an op twice: the count", g(sa([blue, blue]), "uber.vv.u1-x.mA"), "1")
    C.Check.str("a gap is not taken", g(sa([gone]), "uber.vv.u1-x.mA"), "-")
    C.Check.str("forget after save", g(sa([blue, red, gone]), "uber.r.u1-x.mem:color"), UO.Ub.b.forget("color"))
    C.Check.str("forget is a tombstone in any order", dig(sa([blue, gone, red])), dig(sa([red, blue, gone])))
    C.Check.str("forget loses to a later save", dig(sa([blue, gone, red])), dig(sa([blue, red, gone])))
    C.Check.str("an older forget does not win", g(sa([blue, red, op("mB", 2n, 999n, 0n, UO.Ub.b.forget("color"))]), "uber.r.u1-x.mem:color"), UO.Ub.b.mem("color", "fact", "red", ""))
    C.Check.str("origins", g(sa([blue, red]), "uber.origins.u1-x"), "mA mB")
    C.Check.str("origins, other order", g(sa([red, blue]), "uber.origins.u1-x"), "mA mB")
    C.Check.str("interleaving 1", dig(sa([blue, gone, red, sp])), "{\"k\":\"forget\",\"key\":\"color\"}|0000001002.000000.mA|{\"k\":\"space\",\"spec\":\"{}\"}|-|2|2|-|mA mB")
    C.Check.str("interleaving 2", dig(sa([blue, red, gone, sp])), dig(sa([blue, gone, red, sp])))
    C.Check.str("interleaving 3", dig(sa([blue, red, sp, gone])), dig(sa([blue, gone, red, sp])))
    C.Check.str("interleaving 4", dig(sa([red, blue, gone, sp])), dig(sa([blue, gone, red, sp])))
    C.Check.str("interleaving 5", dig(sa([red, blue, sp, gone])), dig(sa([blue, gone, red, sp])))
    C.Check.str("interleaving 6", dig(sa([red, sp, blue, gone])), dig(sa([blue, gone, red, sp])))
    # compaction: a superseded op is a nop, a loser is one at once
    +m1 : M.Change = op("mA", 1n, 1000n, 0n, UO.Ub.b.mem("color", "fact", "one", ""))
    +m2 : M.Change = op("mA", 2n, 1001n, 0n, UO.Ub.b.mem("color", "fact", "two", ""))
    +m3 : M.Change = op("mA", 3n, 1002n, 0n, UO.Ub.b.mem("color", "fact", "three", ""))
    +s3 : M.State = sa([m1, m2, m3])
    C.Check.str("a key saved three times: the first is a nop", g(s3, "uber.op.u1-x.mA.1"), UO.Ub.line.nop("u1-x", "mA", 1n, UO.Ub.stamp.make(1000n, 0n, "mA")))
    C.Check.str("the second is a nop", g(s3, "uber.op.u1-x.mA.2"), UO.Ub.line.nop("u1-x", "mA", 2n, UO.Ub.stamp.make(1001n, 0n, "mA")))
    C.Check.str("the third keeps its body", g(s3, "uber.op.u1-x.mA.3"), UO.Ub.line("u1-x", "mA", 3n, UO.Ub.stamp.make(1002n, 0n, "mA"), UO.Ub.b.mem("color", "fact", "three", ""), 1002n))
    C.Check.str("the register is the third", g(s3, "uber.rn.u1-x.mem:color"), "mA.3")
    C.Check.str("n stays contiguous", g(s3, "uber.vv.u1-x.mA"), "3")
    C.Check.str("a loser is a nop at once", g(sa([m1, m2, m3, op("mB", 1n, 900n, 0n, UO.Ub.b.mem("color", "fact", "old", ""))]), "uber.op.u1-x.mB.1"), UO.Ub.line.nop("u1-x", "mB", 1n, UO.Ub.stamp.make(900n, 0n, "mB")))
    C.Check.str("same lines in the other order", dig(sa([m1, m2, m3, op("mB", 1n, 900n, 0n, UO.Ub.b.mem("color", "fact", "old", ""))])), dig(sa([m1, m2, op("mB", 1n, 900n, 0n, UO.Ub.b.mem("color", "fact", "old", "")), m3])))
    C.Check.str("a peer lacking them gets nops and the winner", tags(US.Ub.commit(US.Ub.lacking(s3, J.Json.obj(Nil{})), sb(Nil{}))), "UberOp;UberOp;UberOp;MemorySaved;")
    C.Check.str("grace beat", Nat.show(US.Ub.beat.every(600n)) ++ "," ++ Nat.show(US.Ub.beat.every(30n)) ++ "," ++ Nat.show(US.Ub.beat.every(100000n)), "60,7,60")
    +l1 : M.Change = op("mB", 1n, 2000n, 0n, UO.Ub.b.lease("mB", 2n))
    +l2 : M.Change = op("mA", 3n, 2001n, 0n, UO.Ub.b.lease("mA", 2n))
    +l3 : M.Change = op("mA", 3n, 1500n, 0n, UO.Ub.b.lease("mA", 3n))
    +l0 : M.Change = op("mA", 1n, 900n, 0n, UO.Ub.b.lease("mA", 1n))
    C.Check.str("lease same term: one holder either way", US.Ub.holder(sa([l0, l1])), US.Ub.holder(sa([l1, l0])))
    C.Check.str("a term taken twice has one holder", US.Ub.holder(sa([l0, op("mA", 2n, 1990n, 0n, UO.Ub.b.lease("mA", 2n)), l1])), US.Ub.holder(sa([l1, l0, op("mA", 2n, 1990n, 0n, UO.Ub.b.lease("mA", 2n))])))
    C.Check.str("the later stamp holds a shared term", US.Ub.holder(sa([l0, op("mA", 2n, 1990n, 0n, UO.Ub.b.lease("mA", 2n)), l1])), "mB")
    C.Check.str("a higher term wins over a later stamp", US.Ub.holder(sa([l0, op("mA", 2n, 1990n, 0n, UO.Ub.b.lease("mA", 2n)), l1, l3])), "mA")
    C.Check.str("a higher term wins in any order", Nat.show(US.Ub.term(sa([l0, op("mA", 2n, 1990n, 0n, UO.Ub.b.lease("mA", 2n)), l3, l1]))), "3")
    C.Check.str("no lease: this machine holds", yes(US.Ub.holder.me(sa(Nil{}))), "yes")
    C.Check.str("a lease of mA: A holds", yes(US.Ub.holder.me(sa([l0]))), "yes")
    C.Check.str("a lease of mA: B does not", yes(US.Ub.holder.me(sb([l0]))), "no")
    C.Check.str("a lease of mB: A does not", yes(US.Ub.holder.me(sa([l1]))), "no")
    +r1 : M.Change = op("mA", 2n, 1100n, 0n, UO.Ub.b.routine("mA:r1", "Digest", "daily 09:00", "sum up", True{}, ""))
    C.Check.str("fires on the holder", yes(US.Ub.fires(sa([l0, r1]), "mA:r1", 5000n)), "yes")
    C.Check.str("not on another machine", yes(US.Ub.fires(sb([l0, r1]), "mA:r1", 5000n)), "no")
    +f1 : M.Change = op("mA", 3n, 5001n, 0n, UO.Ub.b.fired("mA:r1", 5000n))
    C.Check.str("a slot once", yes(US.Ub.fires(sa([l0, r1, f1]), "mA:r1", 5000n)), "no")
    C.Check.str("an older slot is over", yes(US.Ub.fires(sa([l0, r1, f1]), "mA:r1", 4000n)), "no")
    C.Check.str("the next slot runs", yes(US.Ub.fires(sa([l0, r1, f1]), "mA:r1", 5600n)), "yes")
    C.Check.str("fired by", g(sa([l0, r1, f1]), "uber.firedby.u1-x.mA:r1"), "mA")
    +pin : M.Change = op("mA", 2n, 1100n, 0n, UO.Ub.b.routine("mA:r1", "Digest", "daily 09:00", "sum up", True{}, "mB"))
    C.Check.str("pinned: the pin runs it", yes(US.Ub.fires(sb([l0, pin]), "mA:r1", 5000n)), "yes")
    C.Check.str("pinned: the holder does not", yes(US.Ub.fires(sa([l0, pin]), "mA:r1", 5000n)), "no")
    C.Check.str("pinned stays after a takeover", yes(US.Ub.fires(sb([l0, pin, l1]), "mA:r1", 5000n)), "yes")
    C.Check.str("pinned stays when the other takes over", yes(US.Ub.fires(sa([l0, pin, l1]), "mA:r1", 5000n)), "no")
    C.Check.str("gid", US.Ub.gid("mA", "o5"), "mA:o5")
    C.Check.str("gid keeps a global id", US.Ub.gid("mB", "mA:o5"), "mA:o5")
    C.Check.str("lid", US.Ub.lid("mA", "mA:o5"), "o5")
    C.Check.str("lid of another machine's", US.Ub.lid("mB", "mA:o5"), "mA:o5")
    C.Check.str("takeover: not before the grace", yes(US.Ub.takeover(sb([l0]), 100n, 600n, True{})), "no")
    C.Check.str("takeover: after the grace", yes(US.Ub.takeover(sb([l0]), 600n, 600n, True{})), "yes")
    C.Check.str("takeover: not first", yes(US.Ub.takeover(sb([l0]), 900n, 600n, False{})), "no")
    C.Check.str("takeover: the holder never", yes(US.Ub.takeover(sa([l0]), 900n, 600n, True{})), "no")
    C.Check.str("first of the machines", yes(US.Ub.first(["mC", "mB", "mA"], "mA", "")), "yes")
    C.Check.str("not first", yes(US.Ub.first(["mC", "mB", "mA"], "mB", "")), "no")
    C.Check.str("the holder is not counted", yes(US.Ub.first(["mA", "mC"], "mB", "mA")), "yes")
    C.Check.str("lease body", US.Ub.lease.body(sb([l0])), UO.Ub.b.lease("mB", 2n))
    +s0 : M.State = sa(Nil{})
    C.Check.str("ops for A", tags(US.Ub.ops(s0, 3000n, [UO.Ub.b.forget("a"), UO.Ub.b.forget("b")])), "UberOp;UberOp;")
    C.Check.str("first op", first(US.Ub.ops(s0, 3000n, [UO.Ub.b.forget("a")])), "{\"$\":\"UberOp\",\"uid\":\"u1-x\",\"origin\":\"mA\",\"n\":1,\"stamp\":\"0000003000.000000.mA\",\"op\":\"{\\\"k\\\":\\\"forget\\\",\\\"key\\\":\\\"a\\\"}\",\"at\":3000}")
    C.Check.str("no machine id, no ops", tags(US.Ub.ops(M.State.replay(List.take(&2, M.Change, mk("mA", "b1", "t1", "Kit"), 2n), M.State.empty()), 3000n, [UO.Ub.b.forget("a")])), "")
    C.Check.str("ops follow the log's count", tags(US.Ub.ops(sa([blue]), 3000n, [UO.Ub.b.forget("a")])), "UberOp;")
    C.Check.str("the next op is n 2", Nat.show(J.Json.get_nat(K.Change.encode(Maybe.default(&2, M.Change, List.head(&2, M.Change, US.Ub.ops(sa([blue]), 3000n, [UO.Ub.b.forget("a")])), blue)), "n", 0n)), "2")
    C.Check.str("the next stamp passes the clock", J.Json.get_str(K.Change.encode(Maybe.default(&2, M.Change, List.head(&2, M.Change, US.Ub.ops(sa([op("mB", 1n, 9000n, 4n, UO.Ub.b.forget("z"))]), 3000n, [UO.Ub.b.forget("a")])), blue)), "stamp", ""), "0000009000.000005.mA")
    C.Check.str("also: a memory of the uberbot gets an op", tags(US.Ub.also(s0, 3000n, [M.MemorySaved{"b1", "k", "fact", "t", "", 3000n}])), "MemorySaved;UberOp;")
    C.Check.str("also: another bot's does not", tags(US.Ub.also(s0, 3000n, [M.MemorySaved{"b2", "k", "fact", "t", "", 3000n}])), "MemorySaved;")
    C.Check.str("also: forget, space, page", tags(US.Ub.also(s0, 3000n, [M.MemoryForgot{"b1", "k", 3000n}, M.SpaceSet{"b1", "{}", 3000n}, M.SpacePageSet{"b1", "<p>", 3000n}])), "MemoryForgot;SpaceSet;SpacePageSet;UberOp;UberOp;UberOp;")
    C.Check.str("also: persona", tags(US.Ub.also(s0, 3000n, [M.BotSet{"b1", "Kit", "", 7n, "calm", 3000n}])), "BotSet;UberOp;")
    C.Check.str("also: a routine", tags(US.Ub.also(s0, 3000n, [M.RoutineSet{"o1", "b1", "R", "daily 09:00", "p", True{}, 3000n}])), "RoutineSet;UberOp;")
    C.Check.str("also: a routine's delete", tags(US.Ub.also(sa([]), 3000n, [M.RoutineDeleted{"o1", 3000n}])), "RoutineDeleted;")
    +s1 : M.State = M.State.replay([M.RoutineSet{"o1", "b1", "R", "daily 09:00", "p", True{}, 150n}], s0)
    C.Check.str("also: a routine's delete (the uberbot's)", tags(US.Ub.also(s1, 3000n, [M.RoutineDeleted{"o1", 3000n}])), "RoutineDeleted;UberOp;")
    C.Check.str("no uberbot, no ops", tags(US.Ub.also(M.State.replay(List.take(&2, M.Change, mk("mA", "b1", "t1", "Kit"), 3n), M.State.empty()), 3000n, [M.MemorySaved{"b1", "k", "fact", "t", "", 3000n}])), "MemorySaved;")
    C.Check.str("init: ops of a bare uberbot", tags(US.Ub.init(M.State.replay([M.MemorySaved{"b1", "k", "fact", "t", "", 120n}, M.SpaceSet{"b1", "{}", 121n}], s0), 3000n)), "UberOp;UberOp;UberOp;UberOp;UberOp;")
    C.Check.str("init: once", tags(US.Ub.init(sa([blue]), 3000n)), "")
    C.Check.str("promoted", tags(US.Ub.promoted(M.State.replay(List.take(&2, M.Change, mk("mA", "b1", "t1", "Kit"), 3n), M.State.empty()), "b1", "u9-z", 3000n)), "UberSet;UberOp;UberOp;UberOp;")
    # A's ops reach B: the replica gets them
    +aops : List<&2, M.Change> = US.Ub.init(M.State.replay([M.MemorySaved{"b1", "k", "fact", "t", "", 120n}, M.SpaceSet{"b1", "{}", 121n}], s0), 3000n)
    +sA : M.State = M.State.replay(List.append(&2, M.Change, [M.MemorySaved{"b1", "k", "fact", "t", "", 120n}, M.SpaceSet{"b1", "{}", 121n}], aops), s0)
    C.Check.str("A's vv", J.Json.show(US.Ub.vv(sA)), "{\"mA\":5}")
    +sB : M.State = sb(Nil{})
    C.Check.str("B lacks all of them", n(US.Ub.lacking(sA, J.Json.obj(Nil{}))), "5")
    C.Check.str("B lacks the later ones", n(US.Ub.lacking(sA, J.Json.obj([J.KV{"mA", J.Json.nat(3n)}]))), "2")
    C.Check.str("nothing lacking when equal", n(US.Ub.lacking(sA, US.Ub.vv(sA))), "0")
    +cB : List<&2, M.Change> = US.Ub.commit(US.Ub.lacking(sA, J.Json.obj(Nil{})), sB)
    C.Check.str("B takes them and applies them", tags(cB), "UberOp;BotSet;UberOp;MemorySaved;UberOp;SpaceSet;UberOp;UberOp;")
    +sB2 : M.State = M.State.replay(cB, sB)
    C.Check.str("B's replica has the memory", BT.Mem.text(BT.World.mem(M.State.bots(sB2), "b2", "k")), "t")
    C.Check.str("B's replica has the space", BT.World.space(M.State.bots(sB2), "b2"), "{}")
    C.Check.str("B knows A", J.Json.show(US.Ub.vv(sB2)), "{\"mA\":5}")
    C.Check.str("again changes nothing", tags(US.Ub.commit(US.Ub.lacking(sA, J.Json.obj(Nil{})), sB2)), "")
    C.Check.str("B's bot is not A's", UB.Uber.bot(sB2), "b2")
    C.Check.str("derived changes make no ops", tags(US.Ub.derive(sB, UO.Ub.line.read(Maybe.default(&2, String, List.head(&2, String, US.Ub.lacking(sA, J.Json.obj(Nil{}))), "")))), "BotSet;")
    C.Check.str("a routine arrives under the global id", tags(US.Ub.commit(lines([op("mA", 1n, 1100n, 0n, UO.Ub.b.routine("mA:r1", "Digest", "daily 09:00", "sum up", True{}, ""))]), sB)), "UberOp;RoutineSet;")
    +sB3 : M.State = M.State.replay(US.Ub.commit(lines([op("mA", 1n, 1100n, 0n, UO.Ub.b.routine("mA:r1", "Digest", "daily 09:00", "sum up", True{}, ""))]), sB), sB)
    C.Check.str("the routine's id", BT.Routine.id(BT.World.routine(M.State.bots(sB3), "mA:r1")), "mA:r1")
    C.Check.str("the routine is the replica's", BT.Routine.bot(BT.World.routine(M.State.bots(sB3), "mA:r1")), "b2")
    C.Check.str("A's own routine keeps its local id", tags(US.Ub.commit(lines([op("mB", 1n, 1100n, 0n, UO.Ub.b.routine("mA:r1", "Digest", "daily 09:00", "sum up", True{}, ""))]), sa(Nil{}))), "UberOp;RoutineSet;")
    +fire : List<&2, M.Change> = [op("mA", 2n, 1200n, 0n, UO.Ub.b.fired("mA:r1", 5000n))]
    C.Check.str("a fired op marks the routine fired", tags(US.Ub.commit(lines(fire), sB3)), "UberOp;RoutineFired;")
    +sB4 : M.State = M.State.replay(US.Ub.commit(lines(fire), sB3), sB3)
    C.Check.str("fired: the other machine cannot fire the slot", yes(US.Ub.fires(sB4, "mA:r1", 5000n)), "no")
    C.Check.str("a duplicate is logged", tags(US.Ub.commit(lines([op("mB", 1n, 1300n, 0n, UO.Ub.b.fired("mA:r1", 5000n))]), sB4)), "UberOp;ActivityLogged;")
    C.Check.str("a later slot is no duplicate", tags(US.Ub.commit(lines([op("mB", 1n, 1300n, 0n, UO.Ub.b.fired("mA:r1", 5600n))]), sB4)), "UberOp;RoutineFired;")
    # the exchange
    +req : String = US.Ub.sync.req(sA, "alpha", "")
    C.Check.str("a request names the machine", J.Json.get_str(J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(req), J.Null{}), "p"), "machine", ""), "mA")
    +in1 : US.SyncIn = US.Ub.take(sB, J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(req), J.Null{}), "p"), "p1", 4000n)
    C.Check.str("B takes the request", tags(US.SyncIn.changes(in1)), "UberOp;BotSet;UberOp;MemorySaved;UberOp;SpaceSet;UberOp;UberOp;SettingSet;")
    C.Check.str("it is the same uberbot", yes(US.SyncIn.same(in1)), "yes")
    C.Check.str("A held the lease", yes(US.SyncIn.beat(in1)), "yes")
    C.Check.str("B's offer is not needed", tags(US.SyncIn.changes(US.Ub.take(sb(Nil{}), J.Json.obj(Nil{}), "p1", 4000n))), "")
    +noub : M.State = M.State.replay(List.take(&2, M.Change, mk("mC", "b3", "t3", "Cat"), 3n), M.State.empty())
    C.Check.str("a machine with none keeps the offer", tags(US.SyncIn.changes(US.Ub.take(noub, J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(req), J.Null{}), "p"), "p1", 4000n))), "SettingSet;")
    +offered : M.State = M.State.replay(US.SyncIn.changes(US.Ub.take(noub, J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(req), J.Null{}), "p"), "p1", 4000n)), noub)
    C.Check.str("the offer", M.Setting.get(offered, "uber.offer", ""), "{\"uid\":\"u1-x\",\"name\":\"Kit\",\"look\":7,\"machine\":\"mA\",\"link\":\"p1\"}")
    C.Check.str("offered again changes nothing", tags(US.SyncIn.changes(US.Ub.take(offered, J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(req), J.Null{}), "p"), "p1", 4100n))), "")
    C.Check.str("join: not on offer", US.Join.err(US.Ub.join(noub, "u9")), "that uberbot is not on offer here")
    C.Check.str("join: ok", US.Join.err(US.Ub.join(offered, "u1-x")), "")
    C.Check.str("join: has one already", US.Join.err(US.Ub.join(sb(Nil{}), "u1-x")), "that uberbot is not on offer here")
    C.Check.str("join: the name", US.Join.name(US.Ub.join(offered, "u1-x")), "Kit")
    C.Check.str("join: the look", Nat.show(US.Join.look(US.Ub.join(offered, "u1-x"))), "7")
    C.Check.str("joined", tags(US.Ub.joined(offered, "b4", "t4", "Kit", "u1-x", 5000n)), "UberSet;SettingSet;UberOp;")
    C.Check.str("a request answered", J.Json.get_str(Maybe.default(&2, J.Json, J.Json.parse(US.Ub.sync.ans(sB2, "beta", J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(req), J.Null{}), "p"))), J.Null{}), "machine", ""), "mB")
    C.Check.str("the answer lacks nothing for A", n(US.Ub.lacking(sB2, US.Ub.vv(sA))), "0")
    +back : US.SyncIn = US.Ub.take(sA, Maybe.default(&2, J.Json, J.Json.parse(US.Ub.sync.ans(sB2, "beta", J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(req), J.Null{}), "p"))), J.Null{}), "p2", 4000n)
    C.Check.str("A takes the answer", tags(US.SyncIn.changes(back)), "SettingSet;")
    C.Check.str("A names B's link", yes(Bool.not(US.SyncIn.more(back))), "yes")
    # where it lives
    +sL : M.State = M.State.replay([op("mB", 1n, 1000n, 0n, UO.Ub.b.bind("mB", "b2", "t2", "Kit")), M.SettingSet{"uber.link.u1-x.mB", "p2", 1001n}, op("mB", 2n, 1002n, 0n, UO.Ub.b.lease("mB", 2n))], s0)
    C.Check.str("far replicas", String.join(US.Ub.far(sL), ","), "p2~b2")
    C.Check.str("a replica is hidden", yes(US.Ub.far.is(sL, "p2~b2")), "yes")
    C.Check.str("another far bot is not", yes(US.Ub.far.is(sL, "p2~b9")), "no")
    C.Check.str("a local bot is not", yes(US.Ub.far.is(sL, "b2")), "no")
    C.Check.str("chat goes to the holder's thread", US.Ub.chat(sL), "p2~t2")
    C.Check.str("chat stays here when A holds", US.Ub.chat(sa([l0])), "t1")
    C.Check.str("chat stays here with no lease", US.Ub.chat(sa(Nil{})), "t1")
    C.Check.str("join: has one already", US.Join.err(US.Ub.join(M.State.replay([M.SettingSet{"uber.offer", "{\"uid\":\"u1-x\",\"name\":\"Kit\",\"look\":7}", 9n}], sb(Nil{})), "u1-x")), "this machine has an uberbot already; make it not the uberbot first")
    C.Check.str("handoff of a thread that is not elsewhere", yes(String.is_empty(UX.Xref.handoff("t2", "mB", Nil{}))), "yes")
    C.Check.str("handoff with no mirror", yes(String.is_empty(UX.Xref.handoff("p2~t2", "mB", Nil{}))), "yes")
