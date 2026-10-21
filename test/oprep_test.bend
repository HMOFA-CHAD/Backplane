import Base
import ./check.bend as C
import ../src/core/hub.bend as H
import ../src/core/model.bend as M
import ../src/core/mcp.bend as MC

# Operational reports to the uberbot (hub.bend's Operational.*): a launched
# thread's report, a task's result, watched work's end and a wake for the
# uberbot's own thread are filed in its Mailroom, never posted in its Chat;
# every other thread is told as before.

# the uberbot's thread, made the uberbot or not
def uber(+on: Bool, +s: M.State, +bot: String) -> M.State:
  Bool.pick(M.State, on, M.State.apply(s, M.SettingSet{"uber.bot", bot, 1n}), s)

# messages posted in a thread
def posts(+cs: List<&2, M.Change>, +th: String) -> Nat:
  match cs:
    case Nil{}: 0n
    case M.MessagePosted{+t, _, _, _, _} <> +rest: Nat.add(Bool.pick(Nat, String.eq(t, th), 1n, 0n), posts(rest, th))
    case _ <> +rest: posts(rest, th)

def appends(+os: List<&2, H.Out>) -> Nat:
  match os:
    case Nil{}: 0n
    case H.MailAppend{_, _, _} <> +t: 1n+appends(t)
    case _ <> +t: appends(t)

# the changes a filing commits after its body is written
def pending(+os: List<&2, H.Out>) -> List<&2, M.Change>:
  match os:
    case Nil{}: Nil{}
    case H.MailAppend{_, _, +cs} <> +t: List.append(&2, M.Change, cs, pending(t))
    case _ <> +t: pending(t)

def delivered(+cs: List<&2, M.Change>) -> Nat:
  match cs:
    case Nil{}: 0n
    case M.TaskDelivered{_, _} <> +t: 1n+delivered(t)
    case _ <> +t: delivered(t)

def running(+cs: List<&2, M.Change>, +th: String) -> Nat:
  match cs:
    case Nil{}: 0n
    case M.TurnChanged{+t, M.Running{}, _} <> +rest: Nat.add(Bool.pick(Nat, String.eq(t, th), 1n, 0n), running(rest, th))
    case _ <> +rest: running(rest, th)

# the changes without TaskDelivered (a crash after the header, before it)
def undelivered(+cs: List<&2, M.Change>) -> List<&2, M.Change>:
  match cs:
    case Nil{}: Nil{}
    case M.TaskDelivered{_, _} <> +t: undelivered(t)
    case +h <> +t: h <> undelivered(t)

def cs(+st: H.Step) -> List<&2, M.Change>:
  match st:
    case H.Step{+c, _}: c

def os(+st: H.Step) -> List<&2, H.Out>:
  match st:
    case H.Step{_, +o}: o

# a task of t1 for t0; t0 is the bot "bu"'s thread
def task(+on: Bool) -> M.State:
  uber(on, M.State.apply(H.Task.demo(False{}), M.BotSet{"bu", "Bub", "t0", 0n, "", 1n}), "bu")

def finish(+on: Bool) -> H.Step:
  H.Task.finish(task(on), 9n, "t1", H.Step{[M.TurnChanged{"t1", M.Completed{}, 9n}], Nil{}})

# a wake tb asked for (Wake.demo: the bot "bot" on tb, waiting on t1's end)
def wake(+on: Bool) -> H.Step:
  H.Wake.demo.step(uber(on, H.Wake.demo(True{}, ["end"]), "bot"))

# watched work of the uberbot's own thread
def work(+on: Bool) -> H.Step:
  H.Watch.end(uber(on, M.State.apply(H.Watch.demo.at(False{}, "tw"), M.BotSet{"bw", "Bub", "tw", 0n, "", 1n}), "bw"), 9n, "tw", "w-1", "exit 0", "")

# the task's report filed (its header committed), but its TaskDelivered torn
def torn() -> M.State:
  M.State.replay(List.append(&2, M.Change, cs(finish(True{})), undelivered(pending(os(finish(True{}))))), task(True{}))

# t1's thread_send to t0 (auto mode)
def send(+on: Bool) -> H.Step:
  MC.Mcp.send.m(True{}, task(on), 9n, "t1", "t0", "status: merged #200", "")

# a deploy's report to t0
def deploy(+on: Bool) -> H.Step:
  H.Lr.send(task(on), 9n, "deploy", "t0", "deploy_main: built and staged")

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("task result to the uberbot: no Chat message", Nat.show(posts(cs(finish(True{})), "t0")), "0")
    C.Check.str("task result to the uberbot: filed once", Nat.show(appends(os(finish(True{})))), "1")
    C.Check.str("task result: delivered only with the filed header", Nat.show(delivered(cs(finish(True{})))) ++ "/" ++ Nat.show(delivered(pending(os(finish(True{}))))), "0/1")
    C.Check.str("task result to the uberbot starts no turn", Nat.show(running(cs(finish(True{})), "t0")), "0")
    C.Check.str("task result to another thread: posted as before", Nat.show(posts(cs(finish(False{})), "t0")) ++ "/" ++ Nat.show(appends(os(finish(False{})))), "1/0")
    C.Check.str("a filed report torn before TaskDelivered: repair commits only it", Nat.show(delivered(cs(H.Task.repair(torn(), 10n)))) ++ "/" ++ Nat.show(appends(os(H.Task.repair(torn(), 10n)))), "1/0")
    C.Check.str("a wake the uberbot asked for: no Chat message", Nat.show(posts(cs(wake(True{})), "tb")), "0")
    C.Check.str("a wake the uberbot asked for: filed", Nat.show(appends(os(wake(True{})))), "1")
    C.Check.str("a wake the uberbot asked for: rides into a turn it starts", Nat.show(running(cs(wake(True{})), "tb")), "1")
    C.Check.str("a wake for another thread: sent as before", Nat.show(H.Lr.count(cs(wake(False{})), "tb")) ++ "/" ++ Nat.show(appends(os(wake(False{})))), "1/0")
    C.Check.str("watched work of the uberbot: no Chat message", Nat.show(posts(cs(work(True{})), "tw")), "0")
    C.Check.str("watched work of the uberbot: filed, starts no turn", Nat.show(appends(os(work(True{})))) ++ "/" ++ Nat.show(running(cs(work(True{})), "tw")), "1/0")
    C.Check.str("a thread's thread_send to the uberbot: no Chat message", Nat.show(posts(cs(send(True{})), "t0")), "0")
    C.Check.str("a thread's thread_send to the uberbot: filed, starts no turn", Nat.show(appends(os(send(True{})))) ++ "/" ++ Nat.show(running(cs(send(True{})), "t0")), "1/0")
    C.Check.str("thread_send to another thread: delivered as before", Nat.show(posts(cs(send(False{})), "t0")) ++ "/" ++ Nat.show(appends(os(send(False{})))), "1/0")
    C.Check.str("a deploy's report to the uberbot: filed, not in Chat", Nat.show(appends(os(deploy(True{})))) ++ "/" ++ Nat.show(posts(cs(deploy(True{})), "t0")), "1/0")
    C.Check.str("watched work of another thread: told as before", Nat.show(posts(cs(work(False{})), "tw")) ++ "/" ++ Nat.show(appends(os(work(False{})))), "1/0")
