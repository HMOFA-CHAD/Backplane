import Base
import ./check.bend as C
import ../src/core/acp.bend as A
import ../src/core/omp.bend as O
import ../src/core/dialog.bend as D
import ../src/core/json.bend as J

# Oh My Pi's RPC turn (src/core/omp.bend) and its approval answers
# (src/core/dialog.bend). Lines shaped as omp 18.12.6's `--mode rpc-ui`
# writes them (recorded 2026-10-25 from the real omp).

def turn(+sid: String, ask: Bool) -> O.OmpTurn:
  O.OmpTurn{A.AcpTurn{"/tmp/p", "http://127.0.0.1:1/mcp/t?token=x", "", "hello", sid, ask}, "", ""}

def emits(o: A.AcpOut) -> String:
  match o:
    case A.AcpOut{_, _, emit, _}:
      String.join(emit, " | ")

def sends(o: A.AcpOut) -> String:
  match o:
    case A.AcpOut{_, send, _, _}:
      String.join(send, " | ")

def asks(o: A.AcpOut) -> String:
  match o:
    case A.AcpOut{_, _, _, ks}:
      String.join(ks, " | ")

def st(o: A.AcpOut) -> A.Acp:
  match o:
    case A.AcpOut{a, _, _, _}:
      a

def done(a: A.Acp) -> String:
  match a:
    case A.Acp{_, _, True{}, _}:
      "done"
    case A.Acp{_, _, False{}, _}:
      "open"

def has(+s: String, +x: String) -> String:
  Bool.pick(String, String.contains(s, x), "yes", "no")

def state(+count: String) -> String:
  "{\"id\":\"1\",\"type\":\"response\",\"command\":\"get_state\",\"success\":true,\"data\":{\"sessionId\":\"01a1740d\",\"messageCount\":" ++ count ++ ",\"systemPrompt\":\"long\"}}"

def approval() -> String:
  "{\"type\":\"extension_ui_request\",\"id\":\"15b4\",\"method\":\"select\",\"title\":\"Allow tool: bash\\nCommand: echo omp-ok\",\"options\":[\"Approve\",\"Approve bash for this session\",\"Deny\"]}"

def stats() -> String:
  "{\"id\":\"3\",\"type\":\"response\",\"command\":\"get_session_stats\",\"success\":true,\"data\":{\"sessionId\":\"01a1740d\",\"tokens\":{\"input\":16504,\"output\":102,\"reasoning\":0,\"cacheRead\":40,\"cacheWrite\":0,\"total\":16606},\"cost\":0.0127605,\"contextUsage\":{\"tokens\":8287,\"contextWindow\":1048576,\"percent\":0.79}}}"

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("first lines: deltas only, then the session", O.Omp.init(),
      "{\"id\":\"0\",\"type\":\"set_event_filter\",\"events\":null,\"messageUpdates\":\"delta\"}\n{\"id\":\"1\",\"type\":\"get_state\"}")
    +a0 : A.Acp = A.Acp.new()
    +o1 : A.AcpOut = O.Omp.line(a0, turn("", True{}), state("0"))
    C.Check.str("the session opens: the prompt goes", sends(o1), "{\"id\":\"2\",\"type\":\"prompt\",\"message\":\"hello\"}")
    C.Check.str("and its id is the thread's", emits(o1), "{\"type\":\"thread.started\",\"thread_id\":\"01a1740d\"}")
    C.Check.str("a resumed thread with no conversation left is told once", has(emits(O.Omp.line(a0, turn("01a1740d", True{}), state("0"))), "no saved conversation"), "yes")
    C.Check.str("a resumed thread with its conversation is not", has(emits(O.Omp.line(a0, turn("01a1740d", True{}), state("5"))), "notice"), "no")
    +a1 : A.Acp = st(o1)
    C.Check.str("text streams", emits(O.Omp.line(a1, turn("", True{}), "{\"type\":\"message_update\",\"messageId\":\"m\",\"message\":{\"role\":\"assistant\"},\"assistantMessageEvent\":{\"type\":\"text_delta\",\"contentIndex\":0,\"delta\":\"Hi\"}}")),
      "{\"type\":\"item.delta\",\"text\":\"Hi\"}")
    C.Check.str("a tool call is logged by what it does", emits(O.Omp.line(a1, turn("", True{}), "{\"type\":\"tool_execution_start\",\"toolCallId\":\"c1\",\"toolName\":\"bash\",\"args\":{\"command\":\"echo omp-ok\"}}")),
      "{\"type\":\"item.completed\",\"item\":{\"type\":\"command_execution\",\"id\":\"c1\",\"command\":\"echo omp-ok\"}}")
    C.Check.str("a Backplane tool through omp's xd:// by its name", has(emits(O.Omp.line(a1, turn("", True{}), "{\"type\":\"tool_execution_start\",\"toolCallId\":\"c2\",\"toolName\":\"write\",\"args\":{\"content\":\"{}\",\"path\":\"xd://mcp__backplane__thread_list\"}}")), "backplane thread_list"), "yes")
    +ap : A.AcpOut = O.Omp.line(a1, turn("", True{}), approval())
    C.Check.str("an approval goes to the person", has(asks(ap), "\"kind\":\"approval\""), "yes")
    C.Check.str("with the tool and what it would do", has(asks(ap), "\"tool\":\"bash\",\"detail\":\"Command: echo omp-ok\""), "yes")
    C.Check.str("accepted: Approve", D.Dlg.reply(asks(ap), "accept"), "{\"type\":\"extension_ui_response\",\"id\":\"15b4\",\"value\":\"Approve\"}")
    C.Check.str("for the session: its label", D.Dlg.reply(asks(ap), "session"), "{\"type\":\"extension_ui_response\",\"id\":\"15b4\",\"value\":\"Approve bash for this session\"}")
    C.Check.str("declined: Deny", D.Dlg.reply(asks(ap), "decline"), "{\"type\":\"extension_ui_response\",\"id\":\"15b4\",\"value\":\"Deny\"}")
    C.Check.str("in a mode that asks nothing: approved at once", sends(O.Omp.line(a1, turn("", False{}), approval())), "{\"type\":\"extension_ui_response\",\"id\":\"15b4\",\"value\":\"Approve\"}")
    +qq : A.AcpOut = O.Omp.line(a1, turn("", True{}), "{\"type\":\"extension_ui_request\",\"id\":\"q1\",\"method\":\"select\",\"title\":\"Which colour?\",\"options\":[\"Red\",\"Blue\"]}")
    C.Check.str("an ask is a question", has(asks(qq), "\"kind\":\"question\""), "yes")
    C.Check.str("answered with its choice", D.Dlg.reply(asks(qq), "Blue"), "{\"type\":\"extension_ui_response\",\"id\":\"q1\",\"value\":\"Blue\"}")
    +done1 : A.AcpOut = O.Omp.line(a1, turn("", True{}), "{\"type\":\"prompt_result\",\"id\":\"2\",\"agentInvoked\":true,\"status\":\"completed\",\"sessionSettled\":true}")
    C.Check.str("the run completed: the session's totals are asked", sends(done1), "{\"id\":\"3\",\"type\":\"get_session_stats\"}")
    +a2 : A.Acp = st(O.Omp.line(a1, turn("", True{}), "{\"type\":\"message_update\",\"messageId\":\"m\",\"message\":{\"role\":\"assistant\"},\"assistantMessageEvent\":{\"type\":\"text_delta\",\"contentIndex\":0,\"delta\":\"Hi\"}}"))
    +said : A.AcpOut = O.Omp.line(st(O.Omp.line(a2, turn("", True{}), "{\"type\":\"prompt_result\",\"id\":\"2\",\"agentInvoked\":true,\"status\":\"completed\",\"sessionSettled\":true}")), turn("", True{}), stats())
    C.Check.str("the reply, whole, before the turn ends", has(emits(said), "{\"type\":\"item.completed\",\"item\":{\"type\":\"agent_message\",\"text\":\"Hi\"}}"), "yes")
    +end : A.AcpOut = O.Omp.line(st(done1), turn("", True{}), stats())
    C.Check.str("then the turn ends", done(st(end)), "done")
    C.Check.str("with its context fill and the session's totals as Codex's", emits(end),
      "{\"type\":\"context.usage\",\"used\":8287,\"window\":1048576} | {\"type\":\"turn.completed\",\"usage\":{\"input_tokens\":16544,\"cached_input_tokens\":40,\"cache_write_input_tokens\":0,\"output_tokens\":102,\"reasoning_output_tokens\":0,\"cost_usd\":0.0127605}}")
    +bad : A.AcpOut = O.Omp.line(a1, turn("", True{}), "{\"type\":\"prompt_result\",\"id\":\"2\",\"agentInvoked\":true,\"status\":\"error\",\"error\":{\"message\":\"No API key found\",\"retryable\":false},\"sessionSettled\":true}")
    C.Check.str("a failed run fails the turn, with how to fix it", has(emits(bad), "sign Oh My Pi in once"), "yes")
    C.Check.str("a builtin command ends the turn at once", done(st(O.Omp.line(a1, turn("", True{}), "{\"id\":\"2\",\"type\":\"response\",\"command\":\"prompt\",\"success\":true,\"data\":{\"agentInvoked\":false}}"))), "done")
    C.Check.str("the conversation in a line is not read", emits(O.Omp.line(a1, turn("", True{}), "{\"type\":\"agent_end\",\"messages\":[{\"role\":\"user\"}]}")), "")
    C.Check.str("the extension registers Backplane's tools under Claude's names", has(O.Omp.ext(), "'mcp__backplane__' + t.name"), "yes")
