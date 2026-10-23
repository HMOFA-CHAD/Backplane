import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/client.bend as U
import ../src/core/plane.bend as P
import ../src/core/codec.bend as K
import ../src/core/hub.bend as B
import ../src/core/ride.bend as R

# Reduced event fixtures from the stale-plane incident: an ended row retained
# for delivery, a live review monitor, and a coordinator with three inputs.
def base() -> M.State:
  M.State.replay([M.ProjectCreated{"p", "Test", "/tmp/status", 1n},
    M.ThreadCreated{"t", "p", "Thread", M.Local{}, "", "", "codex", "", 1n},
    M.TurnChanged{"t", M.Completed{}, 2n}], M.State.empty())

def state(extra: List<&2, M.Change>) -> M.State:
  M.State.replay(extra, base())

def watched(+doing: String) -> M.State:
  state([M.WorkSet{"t", "watch", "watch-id\t" ++ doing ++ "\t\tApple review\twatch\trun\tPRIVATE_COMMAND", 3n}])

def ended() -> M.State:
  watched(M.Bg.ended.mark() ++ "unknown")

def ui(s: M.State) -> U.Ui:
  U.Ui.online(U.Ui.far.st(U.Ui.init(20n), s), True{})

def current(s: M.State) -> P.Plane:
  P.Plane.of.st(s, 20n)

def words(s: M.State) -> String:
  P.Plane.read(s, 20n, "", "test", True{})

def run(s: M.State) -> String:
  String.join(P.Plane.ids(P.Plane.run(current(s))), ",")

def states(rs: List<&2, P.PRow>) -> String:
  match rs:
    case Nil{}: ""
    case r <> rest: P.PRow.state(r) ++ "," ++ states(rest)

def pending() -> M.State:
  state([M.TurnChanged{"t", M.Running{}, 3n}, M.TurnQueued{"t", "handoff:exact", "context", 4n},
    M.SettingSet{R.Ride.key("t"), R.Ride.show([R.RItem{"exact-1", "one"}, R.RItem{"exact-2", "two"}, R.RItem{"exact-3", "three"}]), 5n}])

def end() -> B.Step:
  B.Step{[M.MessagePosted{"t", "empty-exact", M.Assistant{}, "", 6n}, M.TurnChanged{"t", M.Completed{}, 6n}], Nil{}}

def after(+s: M.State, +step: B.Step) -> M.State:
  M.State.replay(B.Queue.changes(step), s)

def turns(os: List<&2, B.Out>) -> String:
  match os:
    case Nil{}: ""
    case B.CodexTurn{_, _, _, _, _, text} <> rest: text ++ "|" ++ turns(rest)
    case _ <> rest: turns(rest)

def main() -> IO(Unit):
  +watch = watched("watching")
  +started = B.Ride.after(pending(), 6n, end())
  +post = after(pending(), started)
  +parent = state([M.ThreadCreated{"child", "p", "Actual worker", M.Local{}, "", "", "codex", "", 3n},
    M.ThreadLaunched{"child", "t", True{}, 3n}, M.TurnChanged{"child", M.Running{}, 4n}])
  do IO<Unit>:
    C.Check.str("legacy mismatch reproduced by retained ended row", P.Plane.state(U.Side.phase(ended(), U.Ui.thread(ended(), "t"))), "working")
    C.Check.str("ended retained row is not running in current plane", run(ended()), "")
    C.Check.str("ended row remains retained for normal delivery", Nat.show(M.Work.rows(ended(), "t")), "1")
    C.Check.str("inactive row gives actual completed turn", Bool.show(String.contains(words(ended()), "agent: completed")), "True")
    C.Check.str("idle false omits stale working row", Bool.show(String.contains(P.Plane.read(ended(), 20n, "", "test", False{}), "- t ·")), "False")
    C.Check.str("live monitor belongs in waiting work", states(P.Plane.run(current(watch))), "waiting,")
    C.Check.str("waiting work identity and title shown", Bool.show(String.contains(words(watch), "watch-id (Apple review: watching)")), "True")
    C.Check.str("watched command not exposed", Bool.show(String.contains(words(watch), "PRIVATE_COMMAND")), "False")
    C.Check.str("raw completed turn unchanged by presentation", K.Turn.name(M.Thread.turn(U.Ui.thread(watch, "t"))), "completed")
    C.Check.str("unknown work is not confirmed active", run(watched("unknown")), "")
    C.Check.str("launching work is not confirmed active", run(watched("launching")), "")
    C.Check.str("queued work is not confirmed active", run(watched("queued")), "")
    C.Check.str("an actual running agent stays working", states(P.Plane.run(current(state([M.TurnChanged{"t", M.Running{}, 4n}])))), "working,")
    C.Check.str("question still needs person", states(P.Plane.need(current(state([M.AskOpened{"ask-exact", "t", "input", "", "Choose", "", 4n}])))), "question,")
    C.Check.str("failure stays failed", states(P.Plane.need(current(state([M.TurnChanged{"t", M.Failed{}, 4n}])))), "failed,")
    C.Check.str("coordinator distinguishes actual child from own turn", states(P.Plane.run(current(parent))), "working,waiting,")
    C.Check.str("coordinator names actual awaited child", Bool.show(String.contains(words(parent), "child (Actual worker)")), "True")
    C.Check.str("hub plane and display plane agree", P.Plane.text(current(watch), "", "test", 20n, True{}), P.Plane.text(P.Plane.signals.of(ui(watch), 20n, True{}), "", "test", 20n, True{}))
    C.Check.str("empty reply with pending input starts once with all inputs", turns(B.Step.outs_of(started)), "context\n\none\n\ntwo\n\nthree|")
    C.Check.str("delivery preserves exact ride order and identities", String.join(R.Ride.ids(R.Ride.read(B.Ride.of(pending(), "t"))), ","), "exact-1,exact-2,exact-3")
    C.Check.str("followup consumes ride once", B.Ride.of(post, "t"), "")
    C.Check.str("followup consumes handed context once", M.Queue.of(post, "t"), "")
    C.Check.str("empty followup with no input does not busy loop", turns(B.Step.outs_of(B.Ride.after(post, 7n, end()))), "")
    C.Check.str("same completed followup is idle with no active work", run(after(post, end())), "")
