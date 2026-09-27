import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/hub.bend as H
import ../src/core/client.bend as U

# Claude's subagents: a background one started, said what it does, and
# ended (lines as Claude Code 2.1 writes them); the thread waits on it
# after its own turn ends, and an agent that exits leaves none at work.

def base() -> List<&2, M.Change>:
  [M.ProjectCreated{"p1", "P", "/r/board", 50n}]

def state(es: List<&2, M.Change>) -> M.State:
  M.State.replay(es, M.State.empty())

def after.req(+es: List<&2, M.Change>, +now: Nat, +text: String) -> List<&2, M.Change>:
  List.append(&2, M.Change, es, H.Queue.changes(H.Hub.request_text(state(es), now, 1, text)))

# the log after one line of the agent's output
def after(+es: List<&2, M.Change>, +now: Nat, +line: String) -> List<&2, M.Change>:
  List.append(&2, M.Change, es, H.Queue.changes(H.Hub.agent_line(state(es), now, "t100-1", line)))

def made() -> List<&2, M.Change>:
  List.append(&2, M.Change, after.req(base(), 100n, "{\"id\":1,\"m\":\"thread.create\",\"p\":{\"project\":\"p1\",\"env\":\"local\"}}"),
    [M.TurnChanged{"t100-1", M.Running{}, 101n}])

def started() -> List<&2, M.Change>:
  after(made(), 102n, "{\"type\":\"system\",\"subtype\":\"task_started\",\"task_id\":\"a847\",\"tool_use_id\":\"toolu_1\",\"description\":\"Run bash command and report output\",\"subagent_type\":\"general-purpose\",\"is_backgrounded\":true,\"task_type\":\"local_agent\",\"session_id\":\"s\"}")

# the agent's own turn ends while the subagent works on
def done() -> List<&2, M.Change>:
  List.append(&2, M.Change, started(), [M.TurnChanged{"t100-1", M.Completed{}, 103n}])

def progressed() -> List<&2, M.Change>:
  after(done(), 104n, "{\"type\":\"system\",\"subtype\":\"task_progress\",\"task_id\":\"a847\",\"tool_use_id\":\"toolu_1\",\"description\":\"Running Sleep for 20 seconds\",\"last_tool_name\":\"Bash\",\"session_id\":\"s\"}")

def ended() -> List<&2, M.Change>:
  after(progressed(), 105n, "{\"type\":\"system\",\"subtype\":\"task_notification\",\"task_id\":\"a847\",\"tool_use_id\":\"toolu_1\",\"status\":\"completed\",\"session_id\":\"s\"}")

def status(+es: List<&2, M.Change>) -> String:
  M.Status.name(U.Side.status(state(es), H.Hub.thread(state(es), "t100-1")))

def phase(+es: List<&2, M.Change>) -> String:
  M.Phase.label(U.Side.phase(state(es), H.Hub.thread(state(es), "t100-1")))

def doings(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      M.Bg.doing(l) <> doings(t)

def doing(+es: List<&2, M.Change>) -> String:
  String.join(doings(M.Bg.of(state(es), "t100-1")), "|")

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("started", doing(started()), "Run bash command and report output")
    C.Check.str("working while the turn runs", status(started()), "working")
    C.Check.str("waiting after the turn", status(done()), "waiting")
    C.Check.str("phase after the turn", phase(done()), "Monitoring 1 task")
    C.Check.str("progress", doing(progressed()), "Running Sleep for 20 seconds")
    C.Check.str("progress again writes nothing", Nat.show(List.length(&2, M.Change, progressed())), Nat.show(List.length(&2, M.Change,
      after(progressed(), 106n, "{\"type\":\"system\",\"subtype\":\"task_progress\",\"task_id\":\"a847\",\"description\":\"Running Sleep for 20 seconds\",\"session_id\":\"s\"}"))))
    C.Check.str("a subagent's bash is not listed", doing(after(done(), 104n, "{\"type\":\"system\",\"subtype\":\"task_started\",\"task_id\":\"b1\",\"description\":\"Sleep\",\"task_type\":\"local_bash\"}")), "Run bash command and report output")
    C.Check.str("ended", doing(ended()), "")
    C.Check.str("ready after", status(ended()), "ready")
    C.Check.str("updated to completed ends it", doing(after(progressed(), 105n, "{\"type\":\"system\",\"subtype\":\"task_updated\",\"task_id\":\"a847\",\"patch\":{\"status\":\"completed\"}}")), "")
    C.Check.str("exit clears", doing(List.append(&2, M.Change, progressed(), H.Queue.changes(H.Hub.agent_gone(state(progressed()), 107n, "t100-1", 0)))), "")
    C.Check.str("restart clears", doing(List.append(&2, M.Change, progressed(), H.Queue.changes(H.Hub.recover(state(progressed()), 107n)))), "")
