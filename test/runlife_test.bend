import Base
import ./check.bend as C
import ./mailtriage_test.bend as F
import ../src/core/model.bend as M
import ../src/core/hub.bend as H
import ../src/core/runlife.bend as L
import ../src/core/cmds.bend as CM
import ../src/core/mail.bend as ML
import ../src/core/mailtriage.bend as T
import ../src/core/mcp.bend as MC
import ../src/core/adopt.bend as A
import ../src/core/notice.bend as N

def check(label: String, value: Bool) -> IO(Unit):
  C.Check.str(label, Bool.show(value), "True")

def idle() -> CM.Cmds:
  CM.Cmds{Nil{}, 1n, False{}}

def ended(+s: M.State, turn: M.TurnState) -> M.State:
  M.State.apply(s, M.TurnChanged{F.runid(F.running()), turn, 20n})

def completed() -> M.State:
  +s = F.running()
  ended(M.State.replay(H.Queue.changes(F.res_step(MC.Mcp.dispose(s, 12n, F.runid(s), F.dispose_args("m1")))), s), M.Completed{})

def can(+s: M.State) -> Bool:
  L.Life.retire(s, F.runid(F.running()), idle(), False{})

def verdict(+s: M.State, +c: CM.Cmds) -> A.AVerdict:
  L.Life.adopt(A.VAdopt{A.AEntry{F.runid(F.running()), 42n, "boot:start", 9n, True{}, "gen", "key", c}}, s)

def stopping(v: A.AVerdict) -> Bool:
  match v:
    case A.VStop{_}: True{}
    case _: False{}

def adopted(v: A.AVerdict) -> Bool:
  match v:
    case A.VAdopt{_}: True{}
    case _: False{}

def terminal_check() -> IO(Unit):
  +s = completed()
  check("1 terminal private SDK releases; ordinary coordinator retained", Bool.and(can(s), Bool.not(L.Life.retire(s, "foh", idle(), False{}))))

def ledger_check() -> IO(Unit):
  +s = completed()
  +th = F.runid(F.running())
  +started = {CM.Cmds{[CM.Cmd{"input", 2n, False{}, ""}], 1n, False{}} : CM.Cmds}
  +resulted = CM.Cmds.see(started, CM.Cmds.o(CM.Cmds.l.result()))
  +done = CM.Cmds.see(resulted, CM.Cmds.o(CM.Cmds.l.lc("input", "completed")))
  +watched = M.State.apply(s, M.WakeSet{"exit-watch", "foh", "thread", th, ["fail"], True{}, "unfinished accepted input", 21n})
  +exit = H.Hub.agent_gone.ledger(watched, 22n, th, 143, "", resulted, False{})
  +reported = Bool.or(Bool.not(List.is_empty(&2, M.Change, H.Queue.changes(exit))), Bool.not(List.is_empty(&2, H.Out, H.Step.outs_of(exit))))
  check("2 result before lifecycle completion and held images retain SDK", Bool.and(Bool.not(L.Life.retire(s, th, resulted, False{})), Bool.and(L.Life.retire(s, th, done, False{}), Bool.and(Bool.not(L.Life.retire(s, th, idle(), True{})), reported))))

def queue_check() -> IO(Unit):
  +s = completed()
  +th = F.runid(F.running())
  +queued = M.State.apply(s, M.TurnQueued{th, "pending", "must not lose", 21n})
  +active = M.State.apply(s, M.TurnChanged{th, M.Running{}, 21n})
  +pending = M.State.apply(s, M.PendingChanged{th, 1n, 21n})
  check("3 active, queued and pending input cannot retire", Bool.and(Bool.not(can(queued)), Bool.and(Bool.not(can(active)), Bool.not(can(pending)))))

def arrival_check() -> IO(Unit):
  +s = F.running()
  +body = F.body("m2", "fyi")
  +committed = F.committed(s, body)
  +queued = M.State.replay(H.Queue.changes(H.Mail.route(committed, 15n, body)), committed)
  +acked = M.State.replay(H.Queue.changes(F.res_step(MC.Mcp.dispose(queued, 16n, F.runid(s), F.dispose_args("m1")))), queued)
  +step = H.Run.after(acked, 20n, H.Step{[M.TurnChanged{F.runid(s), M.Completed{}, 20n}], Nil{}})
  +post = M.State.replay(H.Queue.changes(step), acked)
  +next = M.State.replay(H.Queue.changes(H.Run.queue.start(post, 21n, "b", "c")), post)
  check("4 new arrival binds fresh run; old SDK releases; exact receipts survive", Bool.and(can(post), Bool.and(String.eq(String.join(T.Triage.queue(post, "b", "c"), ","), "m2"), Bool.and(Bool.not(String.eq(F.runid(next), F.runid(s))), String.eq(ML.Run.mail(F.run(next)), "m2")))))

def stop_check() -> IO(Unit):
  +s = F.running()
  +stop = H.Hub.interrupt(s, 20n, 1, "stop", F.runid(s))
  +held = M.State.replay(H.Queue.changes(stop), s)
  +cancelled = {CM.Cmds{[CM.Cmd{"stopped", 4n, False{}, ""}], 1n, False{}} : CM.Cmds}
  check("5 Stop releases cancelled SDK while durable FIFO hold survives", Bool.and(L.Life.retire(held, F.runid(s), cancelled, False{}), Bool.and(T.Triage.held(held, "b", "c"), Bool.and(String.eq(String.join(T.Triage.queue(held, "b", "c"), ","), "m1"), List.is_empty(&2, M.Change, H.Queue.changes(H.Run.queue.start(held, 21n, "b", "c")))))))

def restart_check() -> IO(Unit):
  +done = completed()
  +th = F.runid(F.running())
  +pending = M.State.apply(done, M.TurnQueued{th, "pending", "resume", 21n})
  check("6 restart stops completed inheritance; active/pending session adopted", Bool.and(stopping(verdict(done, idle())), Bool.and(adopted(verdict(F.running(), idle())), adopted(verdict(pending, idle())))))

def approval_check() -> IO(Unit):
  +s = completed()
  +th = F.runid(F.running())
  +asked = M.State.apply(s, M.AskOpened{"a", th, "approval", "Bash", "legitimate hold", "", 21n})
  +source = M.State.apply(s, M.AskOpened{"source", "worker", "approval", "flash", "keep source hold", "", 21n})
  +bg = M.State.apply(s, M.WorkSet{th, "bg", "job\tworking", 21n})
  check("7 real own approval/background retained; source approval untouched", Bool.and(Bool.not(can(asked)), Bool.and(adopted(verdict(asked, idle())), Bool.and(Bool.not(can(bg)), Bool.and(can(source), N.Ask.open(source, "worker"))))))

def external_check() -> IO(Unit):
  +s = completed()
  +th = F.runid(F.running())
  +quiet = H.Hub.agent_gone(s, 21n, th, 143)
  +live = F.running()
  +failed = H.Hub.agent_gone(live, 21n, th, 137)
  +post = M.State.replay(H.Queue.changes(failed), live)
  check("8 external completed exit stays quiet; killed unfinished run fails honestly", Bool.and(List.is_empty(&2, M.Change, H.Queue.changes(quiet)), Bool.and(List.is_empty(&2, H.Out, H.Step.outs_of(quiet)), Bool.and(L.Life.terminal(M.Thread.turn(H.Hub.thread(post, th))), String.eq(M.Setting.get(post, T.Triage.notice.key(th, "m1"), ""), "")))))

def main() -> IO(Unit):
  do IO<Unit>:
    terminal_check()
    ledger_check()
    queue_check()
    arrival_check()
    stop_check()
    restart_check()
    approval_check()
    external_check()
