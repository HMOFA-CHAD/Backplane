import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/hub.bend as B
import ../src/core/codec.bend as CD
import ../src/core/far.bend as FR

# Settling by work: model.bend's Lifecycle.*, hub.bend's Shelve.* (laws
# life_*). Each case is a log, a step, and the settles and wakes the hub
# adds to it.

def one(c: M.Change) -> String:
  match c:
    case M.ThreadSettled{id, manual, at}:
      Bool.pick(String, manual, "manual:", "settle:") ++ id ++ "@" ++ Nat.show(at)
    case M.ThreadWoke{id, at}:
      "wake:" ++ id ++ "@" ++ Nat.show(at)
    case _:
      "other"

def ones(cs: List<&2, M.Change>) -> List<&2, String>:
  match cs:
    case Nil{}:
      Nil{}
    case c <> rest:
      one(c) <> ones(rest)

def show(cs: List<&2, M.Change>) -> String:
  String.join(ones(cs), ",")

def shelf(sh: M.Shelf) -> String:
  match sh:
    case M.Pinned{}: "pinned"
    case M.Active{}: "active"
    case M.Settled{}: "settled"
    case M.Hidden{}: "hidden"
    case M.Snoozed{}: "snoozed"

def shelf_at(+s: M.State, +id: String) -> String:
  shelf(M.Shelf.of(M.State.thread.get(s, id)))

# t1's turn runs, started by a message at 2 (hub.bend's Shelve.demo)
def log(cs: List<&2, M.Change>) -> M.State:
  B.Shelve.demo(cs)

def step(+s: M.State, +cs: List<&2, M.Change>) -> String:
  show(B.Shelve.step(s, cs))

# the state after a step and the hub's settles and wakes
def after(+s: M.State, +cs: List<&2, M.Change>) -> M.State:
  M.State.replay(List.append(&2, M.Change, cs, B.Shelve.step(s, cs)), s)

def done() -> List<&2, M.Change>:
  [M.TurnChanged{"t1", M.Completed{}, 5n}]

def settled() -> List<&2, M.Change>:
  [M.TurnChanged{"t1", M.Completed{}, 5n}, M.ThreadSettled{"t1", False{}, 5n}]

def tickon(+s: M.State, +id: String) -> String:
  show(B.Shelve.tick([M.State.thread.get(s, id)], M.State.navs(s), M.Work.kids.map(s), s, 100n))

# four threads as a log from before the rule leaves them: a finished one
# still active, one the person settled and then wrote to (working again),
# one the person settled while it ran, one settled by itself that works
def old() -> M.State:
  M.State.replay([M.ProjectCreated{"p1", "p", "/p", 1n},
    M.ThreadCreated{"a", "p1", "a", M.Local{}, "", "", "codex", "", 1n}, M.MessagePosted{"a", "ma", M.User{}, "go", 2n},
    M.TurnChanged{"a", M.Running{}, 2n}, M.TurnChanged{"a", M.Completed{}, 3n},
    M.ThreadCreated{"b", "p1", "b", M.Local{}, "", "", "codex", "", 1n}, M.MessagePosted{"b", "mb", M.User{}, "go", 2n},
    M.TurnChanged{"b", M.Running{}, 2n}, M.TurnChanged{"b", M.Completed{}, 3n}, M.ThreadSettled{"b", True{}, 4n},
    M.MessagePosted{"b", "mb2", M.User{}, "again", 6n}, M.TurnChanged{"b", M.Running{}, 6n},
    M.ThreadCreated{"c", "p1", "c", M.Local{}, "", "", "codex", "", 1n}, M.MessagePosted{"c", "mc", M.User{}, "go", 2n},
    M.TurnChanged{"c", M.Running{}, 2n}, M.ThreadSettled{"c", True{}, 4n},
    M.ThreadCreated{"d", "p1", "d", M.Local{}, "", "", "codex", "", 1n}, M.MessagePosted{"d", "md", M.User{}, "go", 2n},
    M.TurnChanged{"d", M.Completed{}, 3n}, M.ThreadSettled{"d", False{}, 4n}, M.TurnChanged{"d", M.Running{}, 6n},
    M.ThreadCreated{"e", "p1", "e", M.Local{}, "", "", "codex", "", 1n}, M.MessagePosted{"e", "me", M.User{}, "go", 2n},
    M.TurnChanged{"e", M.Failed{}, 3n}], M.State.empty())

def ticked() -> M.State:
  M.State.replay(B.Shelve.tick(B.Shelve.threads(old()), M.State.navs(old()), M.Work.kids.map(old()), old(), 100n), old())

def changes(st: B.Step) -> List<&2, M.Change>:
  match st:
    case B.Step{cs, _}: cs

def has(cs: List<&2, M.Change>, +want: String) -> Bool:
  match cs:
    case Nil{}: False{}
    case c <> rest: Bool.or(String.eq(one(c), want), has(rest, want))

# the log as its lines on disk, read back (a restart, a client's reconnect)
def reread(cs: List<&2, M.Change>) -> List<&2, M.Change>:
  match cs:
    case Nil{}: Nil{}
    case c <> rest: Maybe.default(&2, M.Change, CD.Change.decode(CD.Change.encode(c)), M.SettingSet{"bad", "bad", 0n}) <> reread(rest)

def woken() -> List<&2, M.Change>:
  [M.ProjectCreated{"p1", "p", "/p", 1n}, M.ThreadCreated{"t1", "p1", "x", M.Local{}, "", "", "claude", "", 1n},
   M.TurnChanged{"t1", M.Completed{}, 5n}, M.ThreadSettled{"t1", True{}, 6n}, M.TurnChanged{"t1", M.Running{}, 7n}, M.ThreadWoke{"t1", 7n}]

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("finished, nothing out: settles", step(log(Nil{}), done()), "settle:t1@5")
    C.Check.str("finished thread lands on the settled shelf", shelf_at(after(log(Nil{}), done()), "t1"), "settled")
    C.Check.str("turn ends with background work out: stays active", step(log([M.WorkSet{"t1", "bg", "a\tx", 3n}]), done()), "")
    C.Check.str("background work done after the turn: settles", step(log([M.WorkSet{"t1", "bg", "a\tx", 3n}, M.TurnChanged{"t1", M.Completed{}, 5n}]), [M.WorkSet{"t1", "bg", "", 6n}]), "settle:t1@6")
    C.Check.str("watched work holds it", step(log([M.SettingSet{"watch.t1", "w1\twatching", 3n}]), done()), "")
    C.Check.str("watched work done: settles", step(log([M.SettingSet{"watch.t1", "w1\twatching", 3n}, M.TurnChanged{"t1", M.Completed{}, 5n}]), [M.SettingSet{"watch.t1", "", 6n}]), "settle:t1@6")
    C.Check.str("delegated child at work holds its parent", step(log([M.TaskDelegated{"k1", "t1", "t2", 1n, "claude", "", 3n}]), done()), "")
    C.Check.str("child done: parent settles", step(log([M.TaskDelegated{"k1", "t1", "t2", 1n, "claude", "", 3n}, M.TurnChanged{"t1", M.Completed{}, 5n}]), [M.TaskStateSet{"k1", M.TaskDone{}, "ok", 8n}]), "settle:t1@8")
    C.Check.str("pending ask holds it", step(log([M.PendingChanged{"t1", 1n, 3n}]), done()), "")
    C.Check.str("ask answered after the turn: settles", show(B.Shelve.fix(log([M.AskOpened{"a1", "t1", "input", "", "?", "", 3n}, M.PendingChanged{"t1", 1n, 3n}, M.TurnChanged{"t1", M.Completed{}, 4n}]), [M.AskClosed{"a1", "ok", 6n}])), "other,other,settle:t1@6")
    C.Check.str("a message waiting in the queue holds it", step(log([M.TurnQueued{"t1", "m2", "more", 3n}]), done()), "")
    C.Check.str("failure stays for the person", step(log(Nil{}), [M.TurnChanged{"t1", M.Failed{}, 5n}]), "")
    C.Check.str("a stop stays", step(log(Nil{}), [M.TurnChanged{"t1", M.Interrupted{}, 5n}]), "")
    C.Check.str("pinned stays", step(log([M.ThreadPinned{"t1", True{}, 3n}]), done()), "")
    C.Check.str("snoozed stays", step(log([M.ThreadSnoozed{"t1", 100n, 3n}]), done()), "")
    C.Check.str("archived stays", step(log([M.ThreadArchived{"t1", True{}, 3n}]), done()), "")
    C.Check.str("a turn within one second still settles after the message", step(M.State.replay([M.ProjectCreated{"p1", "p", "/p", 1n}, M.ThreadCreated{"t1", "p1", "x", M.Local{}, "", "", "claude", "", 1n},
      M.MessagePosted{"t1", "m1", M.User{}, "go", 5n}, M.TurnChanged{"t1", M.Running{}, 5n}], M.State.empty()), done()), "settle:t1@6")
    C.Check.str("duplicate completion: nothing more", step(log(settled()), [M.TurnChanged{"t1", M.Completed{}, 6n}]), "")
    C.Check.str("stale running event: nothing", step(log(Nil{}), [M.TurnChanged{"t1", M.Running{}, 3n}]), "")
    C.Check.str("new turn wakes a settled thread", step(log(settled()), [M.TurnChanged{"t1", M.Running{}, 7n}]), "wake:t1@7")
    C.Check.str("woken thread is active", shelf_at(after(log(settled()), [M.TurnChanged{"t1", M.Running{}, 7n}]), "t1"), "active")
    C.Check.str("queued message wakes a settled thread", step(log(settled()), [M.TurnQueued{"t1", "m2", "more", 7n}]), "wake:t1@7")
    C.Check.str("background work started wakes a settled thread", step(log(settled()), [M.WorkSet{"t1", "bg", "a\tx", 7n}]), "wake:t1@7")
    C.Check.str("an ask opened wakes a settled thread", show(B.Shelve.fix(log(settled()), [M.AskOpened{"a1", "t1", "input", "", "?", "", 7n}])), "other,other,wake:t1@7")
    C.Check.str("woken, then done: settles again", step(after(log(settled()), [M.TurnChanged{"t1", M.Running{}, 7n}]), [M.TurnChanged{"t1", M.Completed{}, 9n}]), "settle:t1@9")
    C.Check.str("manual settle, then new work: wakes", step(log([M.TurnChanged{"t1", M.Completed{}, 5n}, M.ThreadSettled{"t1", True{}, 6n}]), [M.MessagePosted{"t1", "m2", M.User{}, "again", 7n}, M.TurnChanged{"t1", M.Running{}, 7n}]), "wake:t1@7")
    C.Check.str("manual settle, new work done: settles", step(after(log([M.TurnChanged{"t1", M.Completed{}, 5n}, M.ThreadSettled{"t1", True{}, 6n}]), [M.MessagePosted{"t1", "m2", M.User{}, "again", 7n}, M.TurnChanged{"t1", M.Running{}, 7n}]), [M.TurnChanged{"t1", M.Completed{}, 9n}]), "settle:t1@9")
    C.Check.str("manual settle of a running thread holds", step(log([M.ThreadSettled{"t1", True{}, 3n}]), [M.TurnChanged{"t1", M.Running{}, 4n}]), "")
    C.Check.str("message to a running thread the person settled, same second: wakes", step(log([M.ThreadSettled{"t1", True{}, 3n}]), [M.MessagePosted{"t1", "m2", M.User{}, "more", 3n}]), "wake:t1@3")
    C.Check.str("woken in the same second it was settled is active", shelf_at(after(log([M.ThreadSettled{"t1", True{}, 3n}]), [M.MessagePosted{"t1", "m2", M.User{}, "more", 3n}]), "t1"), "active")
    C.Check.str("message queued for it, same second: wakes", step(log([M.ThreadSettled{"t1", True{}, 3n}]), [M.TurnQueued{"t1", "m2", "more", 3n}]), "wake:t1@3")
    C.Check.str("message queued for it later: wakes", step(log([M.ThreadSettled{"t1", True{}, 3n}]), [M.TurnQueued{"t1", "m2", "more", 4n}]), "wake:t1@4")
    C.Check.str("the agent's own reply leaves the manual settle", step(log([M.ThreadSettled{"t1", True{}, 3n}]), [M.MessagePosted{"t1", "m2", M.Assistant{}, "x", 4n}]), "")
    C.Check.str("a message before the person's settle leaves it", step(log([M.MessagePosted{"t1", "m2", M.User{}, "more", 3n}, M.ThreadSettled{"t1", True{}, 3n}]), [M.TurnChanged{"t1", M.Running{}, 4n}]), "")
    C.Check.str("a message to a settled idle thread waits for its turn", step(log([M.TurnChanged{"t1", M.Completed{}, 5n}, M.ThreadSettled{"t1", True{}, 6n}]), [M.MessagePosted{"t1", "m2", M.User{}, "again", 7n}]), "")
    C.Check.str("a message to another thread leaves this one", step(log([M.ThreadSettled{"t1", True{}, 3n}]), [M.MessagePosted{"t2", "m2", M.User{}, "more", 3n}]), "")
    C.Check.str("manual settle of a running thread: its end stays settled", step(log([M.ThreadSettled{"t1", True{}, 3n}]), done()), "")
    C.Check.str("brought back by the person: not settled by its old turn", step(log([M.TurnChanged{"t1", M.Completed{}, 5n}, M.ThreadSettled{"t1", False{}, 5n}, M.ThreadUnsettled{"t1", 6n}]), [M.TurnChanged{"t1", M.Completed{}, 7n}]), "")
    C.Check.str("brought back, then work: the hold gives way", step(log([M.TurnChanged{"t1", M.Completed{}, 5n}, M.ThreadSettled{"t1", False{}, 5n}, M.ThreadUnsettled{"t1", 6n}]), [M.TurnChanged{"t1", M.Running{}, 7n}]), "wake:t1@7")
    C.Check.str("waking an active thread keeps its place", Nat.show(M.Thread.rank(M.State.thread.get(after(log([M.TurnChanged{"t1", M.Completed{}, 5n}, M.ThreadSettled{"t1", False{}, 5n}, M.ThreadUnsettled{"t1", 6n}]), [M.TurnChanged{"t1", M.Running{}, 7n}]), "t1"))), "6")
    C.Check.str("woken from the settled shelf comes back on top", Nat.show(M.Lifecycle.unsettled_at(M.Thread.woke(9n, M.State.thread.get(log(settled()), "t1")))), "9")
    C.Check.str("tick settles a finished thread left active", tickon(old(), "a"), "settle:a@100")
    C.Check.str("tick wakes a thread written to after its manual settle", tickon(old(), "b"), "wake:b@100")
    C.Check.str("tick leaves a running thread the person settled", tickon(old(), "c"), "")
    C.Check.str("tick wakes a self-settled thread that works", tickon(old(), "d"), "wake:d@100")
    C.Check.str("tick leaves a failure", tickon(old(), "e"), "")
    C.Check.str("tick again: nothing more", show(B.Shelve.tick(B.Shelve.threads(ticked()), M.State.navs(ticked()), M.Work.kids.map(ticked()), ticked(), 101n)), "")
    C.Check.str("shelves after the tick", String.join([shelf_at(ticked(), "a"), shelf_at(ticked(), "b"), shelf_at(ticked(), "c"), shelf_at(ticked(), "d"), shelf_at(ticked(), "e")], ","), "settled,active,settled,active,active")
    C.Check.str("hub tick carries the work rule", Bool.show(has(changes(B.Hub.tick.k(old(), 100n, M.Work.kids.map(old()))), "settle:a@100")), "True")
    C.Check.str("codec round trip", show(reread([M.ThreadWoke{"t1", 7n}])), "wake:t1@7")
    C.Check.str("mirrored to the owner's machines", show([Maybe.default(&2, M.Change, FR.Fr.change("hub", M.ThreadWoke{"t1", 7n}), M.SettingSet{"bad", "bad", 0n})]), "wake:hub~t1@7")
    C.Check.str("a restart reads the same shelf", shelf_at(M.State.replay(reread(woken()), M.State.empty()), "t1"), shelf_at(M.State.replay(woken(), M.State.empty()), "t1"))
    C.Check.str("a woken thread stays active across a reread", shelf_at(M.State.replay(reread(woken()), M.State.empty()), "t1"), "active")
