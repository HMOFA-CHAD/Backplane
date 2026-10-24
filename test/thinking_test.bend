import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/json.bend as J
import ../src/core/hub.bend as H
import ../src/core/codec.bend as CD
import ../src/core/acp.bend as A
import ../src/core/pi.bend as P

# Thinking (model.bend's Think, opt-in): a finished thought is logged as
# an act of tone "thinking" only while the setting is on. Shapes measured
# 2026-10-24: Claude 2.1.286 with --thinking-display summarized gives
# assistant content blocks {"type":"thinking","thinking":...} (empty text
# without the flag); codex 0.155 with model_reasoning_summary gives
# item.completed {"type":"reasoning","text":...}; Pi's message_update
# thinking_end carries the whole thought in "content".

def log() -> List<&2, M.Change>:
  [M.ProjectCreated{"p1", "demo", "/tmp/demo", 1n},
   M.ThreadCreated{"t1", "p1", "Claude work", M.Local{}, "", "", "claude", "haiku", 1n},
   M.ThreadCreated{"t2", "p1", "Codex work", M.Local{}, "", "", "codex", "gpt-6.1-sol", 1n},
   M.TurnChanged{"t1", M.Running{}, 2n}, M.TurnChanged{"t2", M.Running{}, 2n}]

def on(+s: M.State) -> M.State:
  M.State.replay([M.SettingSet{"agent.thinking", "on", 3n}], s)

def acts(cs: List<&2, M.Change>) -> String:
  match cs:
    case Nil{}:
      ""
    case M.ActivityLogged{_, +id, +tone, _, +text, _} <> t:
      tone ++ " " ++ id ++ ": " ++ text ++ "\n" ++ acts(t)
    case _ <> t:
      acts(t)

def changes(st: H.Step) -> List<&2, M.Change>:
  match st:
    case H.Step{cs, _}:
      cs

def claude(+thought: String) -> String:
  "{\"type\":\"assistant\",\"uuid\":\"7a1b2c3d-0000\",\"message\":{\"id\":\"msg_1\",\"role\":\"assistant\",\"content\":[{\"type\":\"thinking\",\"thinking\":\"" ++ thought ++
    "\",\"signature\":\"x\"}],\"usage\":{\"input_tokens\":3,\"output_tokens\":9}}}"

def codex() -> String:
  "{\"type\":\"item.completed\",\"item\":{\"id\":\"item_0\",\"type\":\"reasoning\",\"text\":\"**Counting list items**\"}}"

def emits(o: A.AcpOut) -> String:
  match o:
    case A.AcpOut{_, _, emit, _}:
      String.join(emit, " | ")

def st(o: A.AcpOut) -> A.Acp:
  match o:
    case A.AcpOut{a, _, _, _}:
      a

def state(+sid: String) -> String:
  "{\"id\":\"1\",\"type\":\"response\",\"command\":\"get_state\",\"success\":true,\"data\":{\"thinkingLevel\":\"off\",\"isStreaming\":false,\"sessionId\":\"" ++ sid ++ "\",\"messageCount\":5,\"pendingMessageCount\":0}}"

def main() -> IO(Unit):
  do IO<Unit>:
    +s0 : M.State = M.State.replay(log(), M.State.empty())
    C.Check.str("off unless turned on", Bool.show(M.Think.on(s0)), "False")
    C.Check.str("claude, off: no thought logged", acts(changes(H.Hub.agent_line(s0, 5n, "t1", claude("Let me check 1001.")))), "")
    C.Check.str("claude, on: the thought", acts(changes(H.Hub.agent_line(on(s0), 5n, "t1", claude("Let me check 1001.")))), "thinking think:msg_1:0:7a1b2c3d: Let me check 1001.\n")
    C.Check.str("claude, on, an empty thought (no --thinking-display): nothing", acts(changes(H.Hub.agent_line(on(s0), 5n, "t1", claude("")))), "")
    C.Check.str("codex, off: the reasoning item is dropped", acts(changes(H.Hub.agent_line(s0, 5n, "t2", codex()))), "")
    C.Check.str("codex, on: the summary", Bool.show(String.starts_with(acts(changes(H.Hub.agent_line(on(s0), 5n, "t2", codex()))), "thinking think:item_0-")), "True")
    C.Check.str("a thought survives the log", J.Json.show(CD.Change.encode(M.ActivityLogged{"t1", "think:a", "thinking", "thinking", "x", 5n})),
      "{\"$\":\"ActivityLogged\",\"thread\":\"t1\",\"act\":\"think:a\",\"tone\":\"thinking\",\"kind\":\"thinking\",\"summary\":\"x\",\"at\":5}")
    +old : A.AcpTurn = A.AcpTurn{"/tmp/p", "", "", "hello", "bp-t1-9-0", True{}}
    +a1 : A.Acp = st(P.Pi.line(A.Acp.new(), old, state("bp-t1-9-0")))
    C.Check.str("pi: a thought's end is a reasoning item", emits(P.Pi.line(a1, old,
      "{\"type\":\"message_update\",\"assistantMessageEvent\":{\"type\":\"thinking_end\",\"contentIndex\":0,\"content\":\"The user wants a list.\"}}")),
      "{\"type\":\"item.completed\",\"item\":{\"type\":\"reasoning\",\"text\":\"The user wants a list.\"}}")
