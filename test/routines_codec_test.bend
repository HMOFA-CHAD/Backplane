import Base
import ./check.bend as C
import ../src/core/json.bend as J
import ../src/core/model.bend as M
import ../src/core/codec.bend as CD
import ../src/core/bot.bend as BT

def again.m(m: Maybe<&2, M.Change>) -> String:
  match m:
    case Some{c}:
      J.Json.show(CD.Change.encode(c))
    case None{}:
      "none"

# a change as the log writes it, read back and written again
def again(+c: M.Change) -> String:
  again.m(CD.Change.decode(CD.Change.encode(c)))

def line(+c: M.Change) -> String:
  J.Json.show(CD.Change.encode(c))

def parsed(+text: String) -> String:
  again.m(CD.Change.decode(Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{})))

def routine(+s: M.State, +id: String) -> BT.Routine:
  BT.World.routine(M.State.bots(s), id)

def main() -> IO(Unit):
  do IO<Unit>:
    +plan : M.Change = M.RoutinePlan{"r1", 1790000000n, "person", "remind", 1790000001n}
    +slot : M.Change = M.RoutineSlot{"r1", 1790000600n, 1790000601n}
    +done : M.Change = M.RoutineDone{"r1", 1790000001n}
    +rem : M.Change = M.Reminded{"r1", "b1", "t1", "stand up", 1790000001n}
    C.Check.str("RoutinePlan round trip", again(plan), line(plan))
    C.Check.str("RoutineSlot round trip", again(slot), line(slot))
    C.Check.str("RoutineDone round trip", again(done), line(done))
    C.Check.str("Reminded round trip", again(rem), line(rem))
    C.Check.str("RoutinePlan has its fields", line(plan), "{\"$\":\"RoutinePlan\",\"id\":\"r1\",\"once\":1790000000,\"tz\":\"person\",\"kind\":\"remind\",\"at\":1790000001}")
    C.Check.str("RoutinePlan: missing fields are defaults", parsed("{\"$\":\"RoutinePlan\",\"id\":\"r1\"}"), "{\"$\":\"RoutinePlan\",\"id\":\"r1\",\"once\":0,\"tz\":\"\",\"kind\":\"\",\"at\":0}")
    C.Check.str("Reminded: missing fields are defaults", parsed("{\"$\":\"Reminded\",\"id\":\"r1\"}"), "{\"$\":\"Reminded\",\"id\":\"r1\",\"bot\":\"\",\"thread\":\"\",\"text\":\"\",\"at\":0}")
    C.Check.str("an old RoutineSet still decodes", parsed("{\"$\":\"RoutineSet\",\"id\":\"r1\",\"bot\":\"b1\",\"name\":\"n\",\"cron\":\"daily 09:00\",\"prompt\":\"p\",\"on\":true,\"at\":5}"),
      "{\"$\":\"RoutineSet\",\"id\":\"r1\",\"bot\":\"b1\",\"name\":\"n\",\"cron\":\"daily 09:00\",\"prompt\":\"p\",\"on\":true,\"at\":5}")
    # folding
    +base : List<&2, M.Change> = [M.RoutineSet{"r1", "b1", "n", "daily 09:00", "p", True{}, 100n}, M.RoutineFired{"r1", 200n}]
    +old : M.State = M.State.replay(base, M.State.empty())
    C.Check.str("old log: plan fields stay at their defaults", Nat.show(BT.Routine.once(routine(old, "r1"))) ++ "|" ++ BT.Routine.tz(routine(old, "r1")) ++ "|" ++ BT.Routine.kind(routine(old, "r1")) ++ "|" ++ Bool.show(BT.Routine.done(routine(old, "r1"))), "0|||False")
    C.Check.str("old log: fired sets last", Nat.show(BT.Routine.last(routine(old, "r1"))), "200")
    +planned : M.State = M.State.replay([plan], old)
    C.Check.str("plan sets once, tz, kind", Nat.show(BT.Routine.once(routine(planned, "r1"))) ++ "|" ++ BT.Routine.tz(routine(planned, "r1")) ++ "|" ++ BT.Routine.kind(routine(planned, "r1")), "1790000000|person|remind")
    +fin : M.State = M.State.replay([slot, done], planned)
    C.Check.str("slot and done fold", Nat.show(BT.Routine.slot(routine(fin, "r1"))) ++ "|" ++ Bool.show(BT.Routine.done(routine(fin, "r1"))), "1790000600|True")
    C.Check.str("a done routine stays live", Nat.show(List.length(&2, BT.Routine, BT.World.routines.all(M.State.bots(fin)))), "1")
    C.Check.str("a new plan makes it pending again", Bool.show(BT.Routine.done(routine(M.State.replay([M.RoutinePlan{"r1", 1790009999n, "person", "remind", 1790000700n}], fin), "r1"))) ++ "|" ++ Nat.show(BT.Routine.slot(routine(M.State.replay([M.RoutinePlan{"r1", 1790009999n, "person", "remind", 1790000700n}], fin), "r1"))), "False|0")
    C.Check.str("an edit without a plan keeps it", Nat.show(BT.Routine.once(routine(M.State.replay([M.RoutineSet{"r1", "b1", "n2", "daily 09:00", "p", True{}, 300n}], planned), "r1"))), "1790000000")
    C.Check.str("turning on again resets the slot", Nat.show(BT.Routine.slot(routine(M.State.replay([M.RoutineSet{"r1", "b1", "n", "daily 09:00", "p", False{}, 300n}, M.RoutineSet{"r1", "b1", "n", "daily 09:00", "p", True{}, 400n}], fin), "r1"))), "0")
    +tl : M.State = M.State.replay([M.ThreadCreated{"t1", "", "bot", M.Local{}, "", "", "claude", "", 1n}, rem], M.State.empty())
    C.Check.str("Reminded is a reminder row in the thread", Nat.show(List.length(&2, M.Entry, M.State.mine(tl, "t1"))), "1")
