import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/hub.bend as B
import ../src/core/json.bend as J

# Worktrees made again (model.bend's Worktree.waits, hub.bend's Wt.asked,
# Wt.answered; laws wt_again_*): a message to a thread whose worktree was
# removed asks for it once, a message while that ask is out waits with it,
# and the worktree's arrival runs everything that waited, once.

def changes(st: B.Step) -> List<&2, M.Change>:
  match st:
    case B.Step{cs, _}: cs

def outs(st: B.Step) -> List<&2, B.Out>:
  match st:
    case B.Step{_, os}: os

def again.one(o: B.Out) -> Nat:
  match o:
    case B.Git{_, _, k, _, _, a, _}: Bool.pick(Nat, Bool.and(String.eq(k, "worktree"), String.eq(a, "again")), 1n, 0n)
    case _: 0n

# how many times the step asks for the worktree again
def agains(os: List<&2, B.Out>) -> Nat:
  match os:
    case Nil{}: 0n
    case o <> rest: Nat.add(again.one(o), agains(rest))

def turn(st: M.TurnState) -> String:
  match st:
    case M.Running{}: "running"
    case _: "turn"

def kinds.one(c: M.Change) -> String:
  match c:
    case M.MessagePosted{_, _, _, _, _}: "post"
    case M.TurnQueued{_, _, _, _}: "queued"
    case M.QueueTaken{_, _}: "taken"
    case M.TurnChanged{_, st, _}: turn(st)
    case M.WorktreeSet{_, _, _, _}: "worktree"
    case M.WorktreeSkipped{_, _}: "skipped"
    case M.WorktreeRemoved{_, _}: "removed"
    case M.SettingSet{k, v, _}: Bool.pick(String, String.starts_with(k, "wt.again."), "ask=" ++ v, "setting")
    case _: "other"

def kinds.go(cs: List<&2, M.Change>) -> List<&2, String>:
  match cs:
    case Nil{}: Nil{}
    case c <> rest: kinds.one(c) <> kinds.go(rest)

def kinds(cs: List<&2, M.Change>) -> String:
  String.join(kinds.go(cs), ",")

# the example: t1's turn completed at 5, its worktree removed at 6
def gone() -> M.State:
  B.Wt.demo(Nil{})

def post(+s: M.State, +now: Nat, +msg: String) -> B.Step:
  B.Hub.post(s, now, "t1", msg, M.User{}, "more")

def after(+s: M.State, st: B.Step) -> M.State:
  M.State.replay(changes(st), s)

# the first message, 1 s after the removal
def asked() -> M.State:
  after(gone(), post(gone(), 7n, "m2"))

# a second message while the ask is out
def waiting() -> M.State:
  after(asked(), post(asked(), 20n, "m3"))

def made() -> B.Step:
  B.Wt.ready(waiting(), 25n, 0, "", "t1", M.WorktreeSet{"t1", "b1", "/p/.backplane/worktrees/b1", 25n})

def waits(+s: M.State, +now: Nat) -> String:
  Bool.show(M.Worktree.waits(s, M.State.thread.get(s, "t1"), now))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("the old guard read a just-ended turn as a worktree being made", Bool.show(M.Worktree.pending(M.State.thread.get(gone(), "t1"), 7n)), "True")
    C.Check.str("a just-ended turn's removed worktree is not being made", waits(gone(), 7n), "False")
    C.Check.str("a message 1 s after the removal asks for the worktree once", Nat.show(agains(outs(post(gone(), 7n, "m2")))), "1")
    C.Check.str("and records the ask, keeping the message queued", kinds(changes(post(gone(), 7n, "m2"))), "ask=7,post,queued")
    C.Check.str("a message 100 s after the turn ended asks too", Nat.show(agains(outs(post(gone(), 105n, "m2")))), "1")
    C.Check.str("a message from another thread asks too", Nat.show(agains(outs(B.Hub.inbox.id(gone(), 7n, "t9", "t1", M.User{}, "note", "t:t9:m1")))), "1")
    C.Check.str("while the ask is out the thread waits", waits(asked(), 20n), "True")
    C.Check.str("a second message then asks no second time", Nat.show(agains(outs(post(asked(), 20n, "m3")))), "0")
    C.Check.str("and waits in the queue with the first", kinds(changes(post(asked(), 20n, "m3"))), "post,queued")
    C.Check.str("the worktree comes: the queue runs once and the ask is cleared", kinds(changes(made())), "worktree,ask=,taken,running")
    C.Check.str("after it came nothing waits", waits(after(waiting(), made()), 30n), "False")
    C.Check.str("an ask never answered: after the wait the next message asks again", Nat.show(agains(outs(post(waiting(), 128n, "m4")))), "1")
    C.Check.str("worktree could not be made: the ask is cleared and the queue runs", kinds(changes(B.Wt.ready(waiting(), 25n, 0, "", "t1", M.WorktreeSkipped{"t1", 25n}))), "skipped,ask=,taken,running")
    C.Check.str("a removal clears an ask left behind", kinds(changes(B.Hub.agentm(5n, asked(), 30n, 0, "", J.Json.obj([J.KV{"thread", J.Str{"t1"}}]), "thread.unrooted"))), "removed,ask=")
    C.Check.str("a removal with no ask writes no extra line", kinds(changes(B.Hub.agentm(5n, gone(), 30n, 0, "", J.Json.obj([J.KV{"thread", J.Str{"t1"}}]), "thread.unrooted"))), "removed")
    C.Check.str("a new thread still waits for its first worktree", waits(M.State.replay([M.ProjectCreated{"p1", "p", "/p", 1n}, M.ThreadCreated{"t1", "p1", "x", M.Worktree{}, "", "", "claude", "", 1n}], M.State.empty()), 50n), "True")
    C.Check.str("a new thread's message waits for it, asking nothing", Nat.show(agains(outs(post(M.State.replay([M.ProjectCreated{"p1", "p", "/p", 1n}, M.ThreadCreated{"t1", "p1", "x", M.Worktree{}, "", "", "claude", "", 1n}], M.State.empty()), 50n, "m2")))), "0")
