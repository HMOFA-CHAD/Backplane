import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/json.bend as J
import ../src/core/hub.bend as H
import ../src/core/client.bend as U
import ../src/mobile/notify.bend as Nt

# Work whose owner died is ended, so the phones' island stops counting it
# (hub.bend's Bg.gone, Rec.lost.on, Lost.aside; laws lostwork_*).

# the island's lines, as the phones get them
def island(+s: M.State) -> String:
  J.Json.show(J.Json.arr(Nt.Note.lines.w(U.Ui.threads(s), M.Work.kids.map(s), s)))

def waits(+n: Nat, +th: String) -> String:
  "[{\"thread\":\"" ++ th ++ "\",\"title\":\"" ++ Bool.pick(String, String.eq(th, "t0"), "x", "t1") ++ "\",\"doing\":\"waiting on " ++ Nat.show(n) ++ "\"}]"

# the agent exited
def gone(+s: M.State, +th: String) -> M.State:
  M.State.replay(H.Queue.changes(H.Hub.agent_gone(s, 9n, th, 0)), s)

# a thread with a background shell, idle, continuing on or off
def bg(+on: Bool) -> M.State:
  H.Lost.demo(on, False{})

# the idle parent t0 of a running child task, with a background shell of its own
def parent() -> M.State:
  M.State.replay([M.WorkSet{"t0", "bg", "b1\tsleep 60\tc1\tsleep 60\tshell", 3n}], H.Task.demo(False{}))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("a shell at work is on the island", island(bg(True{})), "[{\"thread\":\"t1\",\"title\":\"t1\",\"doing\":\"waiting on 1\"}]")
    # the agent exits
    C.Check.str("exit, continuing on: no waiting line, the told agent works", island(gone(bg(True{}), "t1")), "[{\"thread\":\"t1\",\"title\":\"t1\",\"doing\":\"Working\"}]")
    C.Check.str("exit, continuing off: island empty", island(gone(bg(False{}), "t1")), "[]")
    C.Check.str("exit, turn running: island empty (the note waits in the queue)", island(gone(H.Lost.demo(True{}, True{}), "t1")), "[]")
    C.Check.str("exit: no rows left", Nat.show(M.Bg.live(M.Bg.of(gone(H.Lost.demo(True{}, True{}), "t1"), "t1"))), "0")
    C.Check.str("exit: the agent is told once", Nat.show(H.Lost.told(M.State.mine(gone(bg(True{}), "t1"), "t1"))), "1")
    C.Check.str("exit twice tells once", Nat.show(H.Lost.told(M.State.mine(gone(gone(bg(True{}), "t1"), "t1"), "t1"))), "1")
    # the hub restarts
    C.Check.str("recover, continuing on: island empty", island(H.Rec.after(bg(True{}), 10n)), "[]")
    C.Check.str("recover, continuing on: rows put aside", Nat.show(List.length(&2, String, H.Lost.stash(H.Rec.after(bg(True{}), 10n), "t1"))), "1")
    C.Check.str("recover then carry: no waiting line, the told agent works", island(H.Carry.after(bg(True{}), 10n)), "[{\"thread\":\"t1\",\"title\":\"t1\",\"doing\":\"Working\"}]")
    C.Check.str("recover then carry: told once", Nat.show(H.Lost.told(M.State.mine(H.Carry.after(bg(True{}), 10n), "t1"))), "1")
    C.Check.str("recover then carry: nothing left aside", Nat.show(List.length(&2, String, H.Lost.stash(H.Carry.after(bg(True{}), 10n), "t1"))), "0")
    C.Check.str("recover, continuing off: no row at work", Nat.show(M.Bg.running(M.Bg.of(H.Rec.after(bg(False{}), 10n), "t1"))), "0")
    C.Check.str("six threads restart: only those that run are listed", island(H.Carry.after(H.Lost.many(), 10n)), "[{\"thread\":\"a1\",\"title\":\"a1\",\"doing\":\"Working\"},{\"thread\":\"a2\",\"title\":\"a2\",\"doing\":\"Working\"},{\"thread\":\"a3\",\"title\":\"a3\",\"doing\":\"Working\"},{\"thread\":\"a4\",\"title\":\"a4\",\"doing\":\"Working\"}]")
    C.Check.str("recover: rows an earlier restart left ended go", island(H.Rec.after(H.Lost.stale(False{}), 10n)), "[]")
    C.Check.str("the same before: they list the thread", island(H.Lost.stale(False{})), "[{\"thread\":\"t1\",\"title\":\"t1\",\"doing\":\"waiting on 1\"}]")
    # a delegated child still running keeps its parent on the island
    C.Check.str("a child and a shell: parent waits on 2", Nat.show(M.Work.busy(parent(), "t0")), "2")
    C.Check.str("exit: the child still keeps the parent waiting", Nat.show(M.Work.busy(gone(parent(), "t0"), "t0")), "1")
    C.Check.str("exit: the child task stays open", Bool.show(H.Task.marked(H.Queue.changes(H.Hub.agent_gone(parent(), 9n, "t0", 0)), "k1")), "False")
    # watched work belongs to the hub, not the agent
    C.Check.str("exit leaves watched work", Nat.show(M.Work.rows(gone(H.Watch.demo.at(False{}, "t1"), "t1"), "t1")), "1")
    # the Live Activity is pushed again when a thread's rows are cleared, and
    # only then (rows change at every subagent step)
    C.Check.str("island touched by rows cleared", Bool.show(H.Island.touch([M.WorkSet{"t1", "bg", "", 3n}])), "True")
    C.Check.str("island not touched by rows set", Bool.show(H.Island.touch([M.WorkSet{"t1", "bg", "b1\tsleep 60", 3n}])), "False")
    C.Check.str("island not touched by watch rows", Bool.show(H.Island.touch([M.WorkSet{"t1", "watch", "", 3n}])), "False")
    C.Check.str("island touched by an agent exit with rows", Bool.show(H.Island.touch(H.Queue.changes(H.Hub.agent_gone(parent(), 9n, "t0", 0)))), "True")
