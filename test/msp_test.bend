import Base
import ./check.bend as C
import ../src/core/acp.bend as A
import ../src/core/msp.bend as S
import ../src/core/json.bend as J

# The Muse MSP translator: a scripted exchange (frames as `muse serve`
# 1.4.6 sends them, trimmed), checked line by line.

def turn(+sid: String) -> S.MspTurn:
  S.MspTurn{"/tmp/p", "http://127.0.0.1:1/mcp/t?token=x", "RULES", "hello", sid, "promptUnmatched", "", "1791825557-42"}

def turn.hi(+sid: String) -> S.MspTurn:
  S.MspTurn{"/tmp/p", "http://127.0.0.1:1/mcp/t?token=x", "RULES", "hello", sid, "allowAll", "high", "1791825557-43"}

def outs(o: A.AcpOut) -> String:
  match o:
    case A.AcpOut{_, send, emit, _}:
      String.join(List.append(&2, String, send, emit), " | ")

def sends(o: A.AcpOut) -> List<&2, String>:
  match o:
    case A.AcpOut{_, send, _, _}:
      send

def emits(o: A.AcpOut) -> String:
  match o:
    case A.AcpOut{_, _, emit, _}:
      String.join(emit, " | ")

def asks(o: A.AcpOut) -> String:
  match o:
    case A.AcpOut{_, _, _, ks}:
      String.join(ks, " | ")

def st(o: A.AcpOut) -> A.Acp:
  match o:
    case A.AcpOut{a, _, _, _}:
      a

def obj(+line: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(line), J.Null{})

def method(+line: String) -> String:
  J.Json.get_str(obj(line), "method", "")

def nth(xs: List<&2, String>, n: Nat) -> String:
  Maybe.default(&2, String, List.head(&2, String, List.drop(&2, String, xs, n)), "")

def params(+line: String) -> J.Json:
  J.Json.get_obj(obj(line), "params")

def done(a: A.Acp) -> String:
  match a:
    case A.Acp{_, _, True{}}:
      "done"
    case A.Acp{_, _, False{}}:
      "open"

def yes(b: Bool) -> String:
  Bool.pick(String, b, "yes", "no")

def main() -> IO(Unit):
  +t = turn("")
  +a0 = A.Acp.new()
  +o1 = S.Msp.line(a0, t, "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{\"experimentalApi\":false,\"grantedCapabilities\":[\"sessionMcp\"],\"serverInfo\":{\"name\":\"muse\",\"version\":\"1.4.6\"}}}")
  +o2 = S.Msp.line(st(o1), t, "{\"id\":2,\"jsonrpc\":\"2.0\",\"result\":{\"session\":{\"sessionId\":\"S1\",\"status\":\"idle\"},\"viewCursor\":\"v:S1:0\"}}")
  +o3 = S.Msp.line(st(o2), t, "{\"jsonrpc\":\"2.0\",\"method\":\"item/delta\",\"params\":{\"delta\":\"Hello —\",\"field\":\"text\",\"itemId\":\"m1\",\"sessionId\":\"S1\",\"viewCursor\":\"v:S1:10.2\"}}")
  +o3r = S.Msp.line(st(o2), t, "{\"jsonrpc\":\"2.0\",\"method\":\"item/delta\",\"params\":{\"delta\":\"thinking\",\"field\":\"summary.0\",\"itemId\":\"r1\",\"sessionId\":\"S1\",\"viewCursor\":\"v\"}}")
  +o3o = S.Msp.line(st(o2), t, "{\"jsonrpc\":\"2.0\",\"method\":\"item/delta\",\"params\":{\"delta\":\"x\",\"itemId\":\"m1\",\"sessionId\":\"OTHER\",\"viewCursor\":\"v\"}}")
  +o4 = S.Msp.line(st(o2), t, "{\"jsonrpc\":\"2.0\",\"method\":\"item/started\",\"params\":{\"item\":{\"args\":\"{\\\"command\\\":\\\"ls\\\",\\\"description\\\":\\\"List workspace files\\\"}\",\"itemId\":\"T1\",\"kind\":\"toolCall\",\"revision\":1,\"status\":\"inProgress\",\"tool\":\"bash\"},\"sessionId\":\"S1\",\"viewCursor\":\"v\"}}")
  +o4r = S.Msp.line(st(o2), t, "{\"jsonrpc\":\"2.0\",\"method\":\"item/started\",\"params\":{\"item\":{\"args\":\"{\\\"path\\\":\\\"src/a.ts\\\"}\",\"itemId\":\"T2\",\"kind\":\"toolCall\",\"revision\":1,\"status\":\"inProgress\",\"tool\":\"read_file\"},\"sessionId\":\"S1\",\"viewCursor\":\"v\"}}")
  +o4c = S.Msp.line(st(o2), t, "{\"jsonrpc\":\"2.0\",\"method\":\"item/started\",\"params\":{\"item\":{\"itemId\":\"R1\",\"kind\":\"reminderChild\",\"revision\":1,\"status\":\"inProgress\"},\"sessionId\":\"S1\",\"viewCursor\":\"v\"}}")
  +o5 = S.Msp.line(st(o2), t, "{\"jsonrpc\":\"2.0\",\"method\":\"item/completed\",\"params\":{\"item\":{\"itemId\":\"T1\",\"kind\":\"toolCall\",\"revision\":3,\"status\":\"completed\",\"tool\":\"bash\"},\"sessionId\":\"S1\",\"viewCursor\":\"v\"}}")
  +o6 = S.Msp.line(st(o2), t, "{\"jsonrpc\":\"2.0\",\"method\":\"item/completed\",\"params\":{\"item\":{\"itemId\":\"m1\",\"kind\":\"agentMessage\",\"revision\":2,\"status\":\"completed\",\"text\":\"Hello — done\"},\"sessionId\":\"S1\",\"viewCursor\":\"v\"}}")
  +o7 = S.Msp.line(st(o2), t, "{\"jsonrpc\":\"2.0\",\"method\":\"session/todoListChanged\",\"params\":{\"items\":[{\"status\":\"completed\",\"text\":\"Read\"},{\"status\":\"inProgress\",\"text\":\"Fix\"}],\"revision\":2,\"sessionId\":\"S1\",\"sourceTool\":\"todo\",\"viewCursor\":\"v\"}}")
  +o8 = S.Msp.line(st(o2), t, "{\"jsonrpc\":\"2.0\",\"method\":\"turn/completed\",\"params\":{\"durationMs\":7363,\"sessionId\":\"S1\",\"terminal\":\"completed\",\"turnId\":\"U\",\"viewCursor\":\"v\"}}")
  +o8f = S.Msp.line(st(o2), t, "{\"jsonrpc\":\"2.0\",\"method\":\"turn/completed\",\"params\":{\"error\":{\"kind\":\"authRequired\",\"message\":\"Not authenticated\",\"retryable\":false},\"sessionId\":\"S1\",\"terminal\":\"failed\",\"turnId\":\"U\",\"viewCursor\":\"v\"}}")
  +o8x = S.Msp.line(st(o2), t, "{\"jsonrpc\":\"2.0\",\"method\":\"turn/completed\",\"params\":{\"sessionId\":\"CHILD\",\"terminal\":\"completed\",\"turnId\":\"U\",\"viewCursor\":\"v\"}}")
  +ob = S.Msp.line(a0, turn("OLD"), "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{}}")
  +ob2 = S.Msp.line(st(ob), turn("OLD"), "{\"id\":2,\"jsonrpc\":\"2.0\",\"result\":{\"session\":{\"sessionId\":\"OLD\"}}}")
  +oh = S.Msp.line(st(S.Msp.line(a0, turn.hi(""), "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{}}")), turn.hi(""), "{\"id\":2,\"jsonrpc\":\"2.0\",\"result\":{\"session\":{\"sessionId\":\"S2\"}}}")
  +oe = S.Msp.line(a0, t, "{\"error\":{\"code\":-32600,\"data\":{\"kind\":\"notInitialized\"},\"message\":\"Not initialized\"},\"id\":2,\"jsonrpc\":\"2.0\"}")
  +oe3 = S.Msp.line(a0, t, "{\"error\":{\"code\":-32030,\"message\":\"noop\"},\"id\":3,\"jsonrpc\":\"2.0\"}")
  +body = {"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"approval/request\",\"params\":{\"approvalId\":\"01a13123-bdf5-7d51-876d-5ba7d639f788\",\"availableChoices\":[{\"choiceId\":\"allow_once\",\"decision\":\"approved\",\"label\":\"Allow once\",\"scope\":\"once\"},{\"choiceId\":\"allow_session\",\"decision\":\"approvedForSession\",\"label\":\"Allow for session\",\"scope\":\"session\"},{\"choiceId\":\"deny\",\"decision\":\"denied\",\"label\":\"Deny\",\"scope\":\"once\"}],\"currentRequirementId\":{\"approvalId\":\"01a13123-bdf5-7d51-876d-5ba7d639f788\",\"sourceIndex\":0},\"itemId\":\"I\",\"rawArgs\":\"{\\\"command\\\":\\\"rm -rf junk\\\"}\",\"sessionId\":\"S1\",\"sourceRange\":{\"first\":{\"id\":\"x\",\"sequence\":55},\"last\":{\"id\":\"y\",\"sequence\":57}},\"subject\":{\"kind\":\"shell\",\"command\":\"rm -rf junk\"},\"toolName\":\"bash\"}}" : String}
  +oq = S.Msp.line(st(o2), t, body)
  +dec = S.Msp.decide(body, "accept")
  do IO<Unit>:
    C.Check.str("msp init method", method(S.Msp.init()), "initialize")
    C.Check.str("msp init mcp", yes(String.contains(S.Msp.init(), "\"sessionMcp\"")), "yes")
    C.Check.str("msp initialized", method(nth(sends(o1), 0n)), "initialized")
    C.Check.str("msp new session", method(nth(sends(o1), 1n)), "session/start")
    C.Check.str("msp new session mode", J.Json.get_str(params(nth(sends(o1), 1n)), "approvalMode", ""), "promptUnmatched")
    C.Check.str("msp new session mcp", J.Json.get_str(J.Json.get_obj(J.Json.get_obj(J.Json.get_obj(params(nth(sends(o1), 1n)), "config"), "mcpServers"), "backplane"), "url", ""), "http://127.0.0.1:1/mcp/t?token=x")
    C.Check.str("msp command id", J.Json.get_str(params(nth(sends(o1), 1n)), "commandId", ""), "00000000-0000-7000-8017-918255574210")
    C.Check.str("msp resume", method(nth(sends(ob), 1n)), "session/resume")
    C.Check.str("msp resume mode first", method(nth(sends(ob2), 0n)), "session/setApprovalMode")
    C.Check.str("msp resume turn", method(nth(sends(ob2), 1n)), "turn/start")
    C.Check.str("msp resume plain", yes(Bool.and(String.contains(nth(sends(ob2), 1n), "\"text\":\"hello\""), Bool.not(String.contains(nth(sends(ob2), 1n), "backplane_instructions")))), "yes")
    C.Check.str("msp opened", method(nth(sends(o2), 0n)), "turn/start")
    C.Check.str("msp rules first", yes(String.contains(nth(sends(o2), 0n), "<backplane_instructions>\\nRULES")), "yes")
    C.Check.str("msp turn id differs", yes(Bool.not(String.eq(J.Json.get_str(params(nth(sends(o2), 0n)), "commandId", ""), J.Json.get_str(params(nth(sends(o1), 1n)), "commandId", "")))), "yes")
    C.Check.str("msp no effort", yes(String.contains(nth(sends(o2), 0n), "reasoningEffort")), "no")
    C.Check.str("msp effort", J.Json.get_str(params(nth(sends(oh), 0n)), "reasoningEffort", ""), "high")
    C.Check.str("msp started", emits(o2), "{\"type\":\"thread.started\",\"thread_id\":\"S1\"}")
    C.Check.str("msp delta", outs(o3), "{\"type\":\"item.delta\",\"text\":\"Hello —\"}")
    C.Check.str("msp reasoning quiet", outs(o3r), "")
    C.Check.str("msp other session quiet", outs(o3o), "")
    C.Check.str("msp tool", outs(o4), "{\"type\":\"item.completed\",\"item\":{\"type\":\"command_execution\",\"id\":\"T1\",\"command\":\"ls\"}}")
    C.Check.str("msp tool path", outs(o4r), "{\"type\":\"item.completed\",\"item\":{\"type\":\"command_execution\",\"id\":\"T2\",\"command\":\"read_file src/a.ts\"}}")
    C.Check.str("msp reminder quiet", outs(o4c), "")
    C.Check.str("msp tool done", outs(o5), "{\"type\":\"tool.done\",\"id\":\"T1\"}")
    C.Check.str("msp message", outs(o6), "{\"type\":\"item.completed\",\"item\":{\"type\":\"agent_message\",\"text\":\"Hello — done\"}}")
    C.Check.str("msp todos", outs(o7), "{\"type\":\"item.updated\",\"item\":{\"type\":\"todo_list\",\"items\":[{\"text\":\"Read\",\"status\":\"completed\"},{\"text\":\"Fix\",\"status\":\"in_progress\"}]}}")
    C.Check.str("msp finished", outs(o8), "{\"type\":\"turn.completed\"}")
    C.Check.str("msp finished state", done(st(o8)), "done")
    C.Check.str("msp failed", outs(o8f), "{\"type\":\"turn.failed\",\"message\":\"Not authenticated (sign in once with `muse login`)\"}")
    C.Check.str("msp child turn quiet", done(st(o8x)), "open")
    C.Check.str("msp open error", outs(oe), "{\"type\":\"turn.failed\",\"message\":\"Not initialized\"}")
    C.Check.str("msp mode error quiet", outs(oe3), "")
    C.Check.str("msp approval receipt", outs(oq), "{\"jsonrpc\":\"2.0\",\"id\":0,\"result\":{}}")
    C.Check.str("msp approval parks", method(asks(oq)), "approval/request")
    C.Check.str("msp decide", method(dec), "approval/decide")
    C.Check.str("msp decide accept", J.Json.get_str(params(dec), "choiceId", ""), "allow_once")
    C.Check.str("msp decide session", J.Json.get_str(params(S.Msp.decide(body, "session")), "choiceId", ""), "allow_session")
    C.Check.str("msp decide decline", J.Json.get_str(params(S.Msp.decide(body, "decline")), "choiceId", ""), "deny")
    C.Check.str("msp decide id", J.Json.get_str(params(dec), "commandId", ""), "01a13123-bdf5-7d51-876d-000000000057")
    C.Check.str("msp decide requirement", J.Json.show(J.Json.get_obj(params(dec), "requirementId")), "{\"approvalId\":\"01a13123-bdf5-7d51-876d-5ba7d639f788\",\"sourceIndex\":0}")
    C.Check.str("msp tool name", S.Msp.tool(params(body)), "bash")
    C.Check.str("msp detail", S.Msp.detail(params(body)), "rm -rf junk")
