import Base
import ./check.bend as C
import ../src/core/acp.bend as A
import ../src/core/opencode.bend as O
import ../src/core/json.bend as J

# opencode's ACP turn (src/core/opencode.bend): resume without replay, a
# lost session opened afresh, tool calls named once their input is known,
# opencode's own failure hints. Lines shaped as opencode 2.1.3 sends them.

def turn(+sid: String) -> A.AcpTurn:
  A.AcpTurn{"/tmp/p", "http://127.0.0.1:1/mcp/t?token=x", "RULES", "hello", sid, False{}}

def turn.ask(+sid: String) -> A.AcpTurn:
  A.AcpTurn{"/tmp/p", "http://127.0.0.1:1/mcp/t?token=x", "RULES", "hello", sid, True{}}

def outs(o: A.AcpOut) -> String:
  match o:
    case A.AcpOut{_, send, emit, _}:
      String.join(List.append(&2, String, send, emit), " | ")

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

def main() -> IO(Unit):
  +a0 = A.Acp.new()
  +old = turn("S0")
  +init = {"{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"protocolVersion\":1,\"agentCapabilities\":{\"loadSession\":true,\"sessionCapabilities\":{\"resume\":{}}}}}" : String}
  +or1 = O.Ocp.line(a0, old, init)
  +on1 = O.Ocp.line(a0, turn(""), init)
  +or2 = O.Ocp.line(a0, old, "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"configOptions\":[]}}")
  +on2 = O.Ocp.line(a0, turn(""), "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"sessionId\":\"S1\"}}")
  +olost = O.Ocp.line(a0, old, "{\"jsonrpc\":\"2.0\",\"id\":2,\"error\":{\"code\":-32602,\"message\":\"session not found: S0\"}}")
  +ocwd = O.Ocp.line(a0, old, "{\"jsonrpc\":\"2.0\",\"id\":2,\"error\":{\"code\":-32602,\"message\":\"session S0 does not belong to cwd: /tmp/p\"}}")
  +onew = O.Ocp.line(a0, old, "{\"jsonrpc\":\"2.0\",\"id\":7,\"result\":{\"sessionId\":\"S2\"}}")
  +onewfail = O.Ocp.line(a0, old, "{\"jsonrpc\":\"2.0\",\"id\":7,\"error\":{\"code\":-32000,\"message\":\"No models are available\"}}")
  +oboom = O.Ocp.line(a0, old, "{\"jsonrpc\":\"2.0\",\"id\":2,\"error\":{\"code\":-32603,\"message\":\"boom\"}}")
  +onf = O.Ocp.line(a0, turn(""), "{\"jsonrpc\":\"2.0\",\"id\":2,\"error\":{\"code\":-32602,\"message\":\"session not found: S0\"}}")
  +oauth = O.Ocp.line(a0, old, "{\"jsonrpc\":\"2.0\",\"id\":3,\"error\":{\"code\":-32000,\"message\":\"Authentication required\"}}")
  +omodel = O.Ocp.line(a0, old, "{\"jsonrpc\":\"2.0\",\"id\":3,\"error\":{\"code\":-32602,\"message\":\"model not found: x/y\"}}")
  +a1 = st(or2)
  +otc = O.Ocp.line(a1, old, upd("{\"sessionUpdate\":\"tool_call\",\"toolCallId\":\"c1\",\"name\":\"bash\",\"title\":\"bash\",\"kind\":\"execute\",\"status\":\"pending\",\"locations\":[],\"rawInput\":{\"cwd\":\"/tmp/p\"}}"))
  +ou1 = O.Ocp.line(st(otc), old, upd("{\"sessionUpdate\":\"tool_call_update\",\"toolCallId\":\"c1\",\"status\":\"in_progress\",\"kind\":\"execute\",\"title\":\"ls -la\",\"locations\":[],\"rawInput\":{\"command\":\"ls -la\",\"cwd\":\"/tmp/p\"}}"))
  +ou2 = O.Ocp.line(st(ou1), old, upd("{\"sessionUpdate\":\"tool_call_update\",\"toolCallId\":\"c1\",\"status\":\"in_progress\",\"kind\":\"execute\",\"title\":\"ls -la\",\"locations\":[],\"rawInput\":{\"command\":\"ls -la\",\"cwd\":\"/tmp/p\"}}"))
  +ou3 = O.Ocp.line(st(ou2), old, upd("{\"sessionUpdate\":\"tool_call_update\",\"toolCallId\":\"c1\",\"status\":\"completed\",\"locations\":[],\"content\":[],\"rawOutput\":{}}"))
  +ord = O.Ocp.line(st(ou3), old, upd("{\"sessionUpdate\":\"tool_call_update\",\"toolCallId\":\"c2\",\"status\":\"in_progress\",\"kind\":\"read\",\"title\":\"read\",\"locations\":[{\"path\":\"/tmp/p/src/a.bend\"}],\"rawInput\":{\"filePath\":\"/tmp/p/src/a.bend\"}}"))
  +ogr = O.Ocp.line(st(ord), old, upd("{\"sessionUpdate\":\"tool_call_update\",\"toolCallId\":\"c3\",\"status\":\"failed\",\"kind\":\"search\",\"title\":\"grep\",\"locations\":[],\"rawInput\":{\"pattern\":\"Ocp\"}}"))
  +ochunk = O.Ocp.line(st(ogr), old, upd("{\"sessionUpdate\":\"agent_message_chunk\",\"messageId\":\"m1\",\"content\":{\"type\":\"text\",\"text\":\"Hi\"}}"))
  +oend = O.Ocp.line(st(ochunk), old, "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"stopReason\":\"end_turn\"}}")
  +oearly = O.Ocp.line(a0, old, upd("{\"sessionUpdate\":\"tool_call_update\",\"toolCallId\":\"c9\",\"status\":\"in_progress\",\"title\":\"ls\",\"rawInput\":{\"command\":\"ls\"}}"))
  +operm = O.Ocp.line(a1, turn.ask("S0"), "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"session/request_permission\",\"params\":{\"sessionId\":\"S0\",\"toolCall\":{\"toolCallId\":\"c4\",\"title\":\"src/a.bend\",\"kind\":\"edit\",\"rawInput\":{\"filePath\":\"/tmp/p/src/a.bend\"}},\"options\":[{\"optionId\":\"once\",\"kind\":\"allow_once\",\"name\":\"Allow once\"},{\"optionId\":\"always\",\"kind\":\"allow_always\",\"name\":\"Always allow\"},{\"optionId\":\"reject\",\"kind\":\"reject_once\",\"name\":\"Reject\"}]}}")
  do IO<Unit>:
    C.Check.str("oc resume method", method(outs(or1)), "session/resume")
    C.Check.str("oc resume keeps session", has(outs(or1), "\"sessionId\":\"S0\""), "yes")
    C.Check.str("oc new method", method(outs(on1)), "session/new")
    C.Check.str("oc resumed prompt", method(outs(or2)), "session/prompt")
    C.Check.str("oc resumed no instructions", has(outs(or2), "<backplane_instructions>"), "no")
    C.Check.str("oc resumed started", has(outs(or2), "{\"type\":\"thread.started\",\"thread_id\":\"S0\"}"), "yes")
    C.Check.str("oc new instructions", has(outs(on2), "<backplane_instructions>\\nRULES"), "yes")
    C.Check.str("oc new started", has(outs(on2), "{\"type\":\"thread.started\",\"thread_id\":\"S1\"}"), "yes")
    C.Check.str("oc lost renews", method(outs(olost)), "session/new")
    C.Check.str("oc lost renew id", rid(outs(olost)), "7")
    C.Check.str("oc lost not ended", done(st(olost)), "open")
    C.Check.str("oc other folder renews", method(outs(ocwd)), "session/new")
    C.Check.str("oc renewed instructions", has(outs(onew), "<backplane_instructions>\\nRULES"), "yes")
    C.Check.str("oc renewed started", has(outs(onew), "{\"type\":\"thread.started\",\"thread_id\":\"S2\"}"), "yes")
    C.Check.str("oc resume error fails", outs(oboom), "{\"type\":\"turn.failed\",\"message\":\"boom\"}")
    C.Check.str("oc resumed no notice", has(outs(or2), "\"type\":\"notice\""), "no")
    C.Check.str("oc renewing no notice yet", emits(olost), "")
    C.Check.str("oc renewed one notice", emits(onew), "{\"type\":\"thread.started\",\"thread_id\":\"S2\"} | {\"type\":\"notice\",\"message\":\"opencode could not resume its session S0, so it started a new one without the earlier conversation. This thread's history in Backplane is kept.\"}")
    C.Check.str("oc renew failed no notice", emits(onewfail), "{\"type\":\"turn.failed\",\"message\":\"No models are available (sign in once with `opencode auth login`)\"}")
    C.Check.str("oc resume error no notice", has(outs(oboom), "\"type\":\"notice\""), "no")
    C.Check.str("oc resume error ends", done(st(oboom)), "done")
    C.Check.str("oc fresh not renewed", method(outs(onf)), "")
    C.Check.str("oc auth hint", outs(oauth), "{\"type\":\"turn.failed\",\"message\":\"Authentication required (sign in once with `opencode auth login`)\"}")
    C.Check.str("oc model hint", outs(omodel), "{\"type\":\"turn.failed\",\"message\":\"model not found: x/y (pick another opencode model in the composer)\"}")
    C.Check.str("oc tool waits for input", outs(otc), "")
    C.Check.str("oc shell named", outs(ou1), "{\"type\":\"item.completed\",\"item\":{\"type\":\"command_execution\",\"id\":\"c1\",\"command\":\"ls -la\"}}")
    C.Check.str("oc tool logged once", outs(ou2), "")
    C.Check.str("oc tool done", outs(ou3), "{\"type\":\"tool.done\",\"id\":\"c1\"}")
    C.Check.str("oc read names file", outs(ord), "{\"type\":\"item.completed\",\"item\":{\"type\":\"command_execution\",\"id\":\"c2\",\"command\":\"read src/a.bend\"}}")
    C.Check.str("oc failed logged and done", outs(ogr), "{\"type\":\"item.completed\",\"item\":{\"type\":\"command_execution\",\"id\":\"c3\",\"command\":\"grep Ocp\"}} | {\"type\":\"tool.done\",\"id\":\"c3\"}")
    C.Check.str("oc text streams", outs(ochunk), "{\"type\":\"item.delta\",\"text\":\"Hi\"}")
    C.Check.str("oc turn ends", has(outs(oend), "{\"type\":\"turn.completed\"}"), "yes")
    C.Check.str("oc turn ends state", done(st(oend)), "done")
    C.Check.str("oc before open ignored", outs(oearly), "")
    C.Check.str("oc permission parks", method(asks(operm)), "session/request_permission")
    C.Check.str("oc permission detail", A.Acp.detail(J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(asks(operm)), J.Null{}), "params")), "/tmp/p/src/a.bend")
    C.Check.str("oc rel", O.Ocp.rel("/tmp/p", "/tmp/p/x"), "x")
    C.Check.str("oc rel outside", O.Ocp.rel("/tmp/p", "/tmp/pq/x"), "/tmp/pq/x")
