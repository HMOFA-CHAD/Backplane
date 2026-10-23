import Base
import ./check.bend as C
import ../src/core/acp.bend as A
import ../src/core/omp.bend as O
import ../src/core/dialog.bend as D
import ../src/core/json.bend as J

# Oh My Pi's ACP turn (src/core/omp.bend) and its form elicitations
# (src/core/dialog.bend). Lines shaped as omp 18.12.6's ACP server
# (src/modes/acp/acp-agent.ts, acp-client-bridge.ts, tools/approval.ts)
# sends them.

def acp(+sid: String, ask: Bool) -> A.AcpTurn:
  A.AcpTurn{"/tmp/p", "http://127.0.0.1:1/mcp/t?token=x", "", "hello", sid, ask}

def turn(+sid: String, +model: String, +effort: String) -> O.OmpTurn:
  O.OmpTurn{acp(sid, True{}), model, effort}

def outs(o: A.AcpOut) -> String:
  match o:
    case A.AcpOut{_, send, emit, _}:
      String.join(List.append(&2, String, send, emit), " | ")

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

def method(+line: String) -> String:
  J.Json.get_str(Maybe.default(&2, J.Json, J.Json.parse(line), J.Null{}), "method", "")

def rid(+line: String) -> String:
  J.Json.as_raw(J.Json.get(Maybe.default(&2, J.Json, J.Json.parse(line), J.Null{}), "id"), "")

def done(a: A.Acp) -> String:
  match a:
    case A.Acp{_, _, True{}, _}:
      "done"
    case A.Acp{_, _, False{}, _}:
      "open"

def has(+s: String, +x: String) -> String:
  Bool.pick(String, String.contains(s, x), "yes", "no")

def upd(+u: String) -> String:
  "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"S0\",\"update\":" ++ u ++ "}}"

def elicit(+props: String, +msg: String) -> String:
  "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"elicitation/create\",\"params\":{\"mode\":\"form\",\"sessionId\":\"S0\",\"message\":\"" ++ msg ++ "\",\"requestedSchema\":{\"type\":\"object\",\"properties\":" ++ props ++ ",\"required\":[\"value\"]}}}"

def main() -> IO(Unit):
  +a0 = A.Acp.new()
  +init = {"{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"protocolVersion\":1,\"agentInfo\":{\"name\":\"omp\",\"version\":\"18.12.6\"},\"authMethods\":[{\"id\":\"agent\"}],\"agentCapabilities\":{\"loadSession\":true,\"sessionCapabilities\":{\"resume\":{}}}}}" : String}
  +ofresh = O.Omp.line(a0, turn("", "", ""), init)
  +oold = O.Omp.line(a0, turn("S0", "", ""), init)
  +nplain = O.Omp.line(a0, turn("", "", ""), "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"sessionId\":\"S1\",\"configOptions\":[]}}")
  +nmodel = O.Omp.line(a0, turn("", "anthropic/claude-opus-5-5", "high"), "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"sessionId\":\"S1\",\"configOptions\":[]}}")
  +neff = O.Omp.line(a0, turn("", "", "auto"), "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"sessionId\":\"S1\"}}")
  +rres = O.Omp.line(a0, turn("S0", "", ""), "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"configOptions\":[]}}")
  +m4 = O.Omp.line(st(nmodel), turn("", "anthropic/claude-opus-5-5", "high"), "{\"jsonrpc\":\"2.0\",\"id\":4,\"result\":{\"configOptions\":[]}}")
  +m5 = O.Omp.line(st(nmodel), turn("", "anthropic/claude-opus-5-5", "high"), "{\"jsonrpc\":\"2.0\",\"id\":5,\"result\":{\"configOptions\":[]}}")
  +m4bad = O.Omp.line(st(nmodel), turn("", "x/y", ""), "{\"jsonrpc\":\"2.0\",\"id\":4,\"error\":{\"code\":-32603,\"message\":\"Unknown ACP model: x/y\"}}")
  +lost = O.Omp.line(a0, turn("S0", "", ""), "{\"jsonrpc\":\"2.0\",\"id\":2,\"error\":{\"code\":-32603,\"message\":\"ACP session not found: S0\"}}")
  +boom = O.Omp.line(a0, turn("S0", "", ""), "{\"jsonrpc\":\"2.0\",\"id\":2,\"error\":{\"code\":-32603,\"message\":\"boom\"}}")
  +renew = O.Omp.line(a0, turn("S0", "", ""), "{\"jsonrpc\":\"2.0\",\"id\":7,\"result\":{\"sessionId\":\"S2\"}}")
  +nokey = O.Omp.line(st(rres), turn("S0", "", ""), "{\"jsonrpc\":\"2.0\",\"id\":3,\"error\":{\"code\":-32603,\"message\":\"No API key found for anthropic.\"}}")
  +chunk = O.Omp.line(st(rres), turn("S0", "", ""), upd("{\"sessionUpdate\":\"agent_message_chunk\",\"content\":{\"type\":\"text\",\"text\":\"Hi\"}}"))
  +tool = O.Omp.line(st(rres), turn("S0", "", ""), upd("{\"sessionUpdate\":\"tool_call\",\"toolCallId\":\"c1\",\"title\":\"Run ls -la\",\"kind\":\"execute\",\"status\":\"pending\",\"rawInput\":{\"command\":\"ls -la\"}}"))
  +tdone = O.Omp.line(st(rres), turn("S0", "", ""), upd("{\"sessionUpdate\":\"tool_call_update\",\"toolCallId\":\"c1\",\"status\":\"completed\"}"))
  +end = O.Omp.line(st(chunk), turn("S0", "", ""), "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"stopReason\":\"end_turn\"}}")
  +perm = O.Omp.line(st(rres), turn("S0", "", ""), "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"session/request_permission\",\"params\":{\"sessionId\":\"S0\",\"toolCall\":{\"toolCallId\":\"c4\",\"title\":\"rm -rf build\",\"kind\":\"execute\",\"rawInput\":{\"command\":\"rm -rf build\"}},\"options\":[{\"optionId\":\"allow_once\",\"kind\":\"allow_once\",\"name\":\"Allow once\"},{\"optionId\":\"allow_always\",\"kind\":\"allow_always\",\"name\":\"Always allow\"},{\"optionId\":\"reject_once\",\"kind\":\"reject_once\",\"name\":\"Reject\"},{\"optionId\":\"reject_always\",\"kind\":\"reject_always\",\"name\":\"Always reject\"}]}}")
  +apr = O.Omp.line(st(rres), turn("S0", "", ""), elicit("{\"value\":{\"type\":\"string\",\"enum\":[\"Approve\",\"Approve write for this session\",\"Deny\"]}}", "Allow tool: write\\nPath: notes/a.txt"))
  +abp = O.Omp.line(st(rres), turn("S0", "", ""), elicit("{\"value\":{\"type\":\"string\",\"enum\":[\"Approve\",\"Deny\"]}}", "Allow tool: mcp__backplane__thread_list\\nOrigin: MCP server tool"))
  +afree = O.Omp.line(st(rres), O.OmpTurn{acp("S0", False{}), "", ""}, elicit("{\"value\":{\"type\":\"string\",\"enum\":[\"Approve\",\"Deny\"]}}", "Allow tool: eval"))
  +q0 = O.Omp.line(st(rres), turn("S0", "", ""), elicit("{\"q0\":{\"type\":\"string\",\"title\":\"Which colour?\",\"anyOf\":[{\"const\":\"Red\",\"title\":\"Red\"},{\"const\":\"Blue\",\"title\":\"Blue\"}]}}", "Questions"))
  +q2 = O.Omp.line(st(rres), turn("S0", "", ""), elicit("{\"q0\":{\"type\":\"string\"},\"q1\":{\"type\":\"string\"}}", "Questions"))
  +yn = O.Omp.line(st(rres), turn("S0", "", ""), elicit("{\"value\":{\"type\":\"boolean\"}}", "Clear the plan?"))
  do IO<Unit>:
    C.Check.str("omp init offers forms", has(O.Omp.init(), "\"elicitation\":{\"form\":{}}"), "yes")
    C.Check.str("omp init method", method(O.Omp.init()), "initialize")
    C.Check.str("omp fresh new", method(sends(ofresh)), "session/new")
    C.Check.str("omp fresh mcp", has(sends(ofresh), "\"mcpServers\":[{\"type\":\"http\",\"name\":\"backplane\""), "yes")
    C.Check.str("omp old resumes", method(sends(oold)), "session/resume")
    C.Check.str("omp old keeps session", has(sends(oold), "\"sessionId\":\"S0\""), "yes")
    C.Check.str("omp plain prompts", method(sends(nplain)), "session/prompt")
    C.Check.str("omp prompt is the text only", has(sends(nplain), "\"prompt\":[{\"type\":\"text\",\"text\":\"hello\"}]"), "yes")
    C.Check.str("omp started", emits(nplain), "{\"type\":\"thread.started\",\"thread_id\":\"S1\"}")
    C.Check.str("omp model first", sends(nmodel), "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"session/set_config_option\",\"params\":{\"sessionId\":\"S1\",\"configId\":\"model\",\"value\":\"anthropic/claude-opus-5-5\"}}")
    C.Check.str("omp thinking without model", has(sends(neff), "\"configId\":\"thinking\",\"value\":\"auto\""), "yes")
    C.Check.str("omp thinking after model", has(sends(m4), "\"configId\":\"thinking\",\"value\":\"high\""), "yes")
    C.Check.str("omp thinking id", rid(sends(m4)), "5")
    C.Check.str("omp prompt after thinking", method(sends(m5)), "session/prompt")
    C.Check.str("omp bad model hint", outs(m4bad), "{\"type\":\"turn.failed\",\"message\":\"Unknown ACP model: x/y (pick another Oh My Pi model in the composer)\"}")
    C.Check.str("omp resumed started", emits(rres), "{\"type\":\"thread.started\",\"thread_id\":\"S0\"}")
    C.Check.str("omp lost renews", method(sends(lost)), "session/new")
    C.Check.str("omp lost renew id", rid(sends(lost)), "7")
    C.Check.str("omp lost no notice yet", emits(lost), "")
    C.Check.str("omp lost not ended", done(st(lost)), "open")
    C.Check.str("omp other error fails", outs(boom), "{\"type\":\"turn.failed\",\"message\":\"boom\"}")
    C.Check.str("omp renewed notice", emits(renew), "{\"type\":\"thread.started\",\"thread_id\":\"S2\"} | {\"type\":\"notice\",\"message\":\"Oh My Pi could not resume its session S0, so it started a new one without the earlier conversation. This thread's history in Backplane is kept.\"}")
    C.Check.str("omp renewed prompts", method(sends(renew)), "session/prompt")
    C.Check.str("omp no key hint", outs(nokey), "{\"type\":\"turn.failed\",\"message\":\"No API key found for anthropic. (sign Oh My Pi in once: run `omp` and use /login, or set the provider's API key)\"}")
    C.Check.str("omp text streams", outs(chunk), "{\"type\":\"item.delta\",\"text\":\"Hi\"}")
    C.Check.str("omp tool logged", outs(tool), "{\"type\":\"item.completed\",\"item\":{\"type\":\"command_execution\",\"id\":\"c1\",\"command\":\"Run ls -la\"}}")
    C.Check.str("omp tool done", outs(tdone), "{\"type\":\"tool.done\",\"id\":\"c1\"}")
    C.Check.str("omp turn ends", outs(end), "{\"type\":\"item.completed\",\"item\":{\"type\":\"agent_message\",\"text\":\"Hi\"}} | {\"type\":\"turn.completed\"}")
    C.Check.str("omp turn ends state", done(st(end)), "done")
    C.Check.str("omp permission parks", method(asks(perm)), "session/request_permission")
    C.Check.str("omp approval parks", method(asks(apr)), "bp/ask")
    C.Check.str("omp approval card", has(asks(apr), "\"kind\":\"approval\",\"proto\":\"elicit\",\"tool\":\"write\",\"detail\":\"Path: notes/a.txt\""), "yes")
    C.Check.str("omp approval sends nothing", outs(apr), "")
    C.Check.str("omp approval once", D.Dlg.reply(asks(apr), "accept"), "{\"jsonrpc\":\"2.0\",\"id\":9,\"result\":{\"action\":\"accept\",\"content\":{\"value\":\"Approve\"}}}")
    C.Check.str("omp approval session", D.Dlg.reply(asks(apr), "session"), "{\"jsonrpc\":\"2.0\",\"id\":9,\"result\":{\"action\":\"accept\",\"content\":{\"value\":\"Approve write for this session\"}}}")
    C.Check.str("omp approval decline", D.Dlg.reply(asks(apr), "decline"), "{\"jsonrpc\":\"2.0\",\"id\":9,\"result\":{\"action\":\"accept\",\"content\":{\"value\":\"Deny\"}}}")
    C.Check.str("omp backplane tool allowed", sends(abp), "{\"jsonrpc\":\"2.0\",\"id\":9,\"result\":{\"action\":\"accept\",\"content\":{\"value\":\"Approve\"}}}")
    C.Check.str("omp backplane tool no ask", asks(abp), "")
    C.Check.str("omp full access allowed", has(sends(afree), "\"value\":\"Approve\""), "yes")
    C.Check.str("omp question parks", has(asks(q0), "\"kind\":\"question\",\"proto\":\"elicit\",\"tool\":\"Oh My Pi\",\"detail\":\"Which colour?\",\"options\":\"Red\\nBlue\",\"key\":\"q0\""), "yes")
    C.Check.str("omp question answer", D.Dlg.reply(asks(q0), "Blue"), "{\"jsonrpc\":\"2.0\",\"id\":9,\"result\":{\"action\":\"accept\",\"content\":{\"q0\":\"Blue\"}}}")
    C.Check.str("omp question dismissed", D.Dlg.reply(asks(q0), ""), "{\"jsonrpc\":\"2.0\",\"id\":9,\"result\":{\"action\":\"cancel\"}}")
    C.Check.str("omp several declined", sends(q2), "{\"jsonrpc\":\"2.0\",\"id\":9,\"result\":{\"action\":\"decline\"}}")
    C.Check.str("omp several said", has(emits(q2), "\"type\":\"notice\""), "yes")
    C.Check.str("omp yes or no", D.Dlg.reply(asks(yn), "Yes"), "{\"jsonrpc\":\"2.0\",\"id\":9,\"result\":{\"action\":\"accept\",\"content\":{\"value\":true}}}")
    C.Check.str("omp yes or no detail", has(asks(yn), "\"detail\":\"Clear the plan?\",\"options\":\"Yes\\nNo\""), "yes")
