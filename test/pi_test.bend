import Base
import ./check.bend as C
import ../src/core/acp.bend as A
import ../src/core/pi.bend as P
import ../src/core/dialog.bend as D
import ../src/core/json.bend as J

# Pi's RPC turn (src/core/pi.bend) and its dialogs (src/core/dialog.bend).
# Lines shaped as pi 1.4.0 sends them (`pi --mode rpc`, recorded against a
# stand-in model server, Backplane's extension loaded).

def turn(+sid: String) -> A.AcpTurn:
  A.AcpTurn{"/tmp/p", "", "", "hello", sid, True{}}

def turn.free(+sid: String) -> A.AcpTurn:
  A.AcpTurn{"/tmp/p", "", "", "hello", sid, False{}}

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

def done(a: A.Acp) -> String:
  match a:
    case A.Acp{_, _, True{}, _}:
      "done"
    case A.Acp{_, _, False{}, _}:
      "open"

def has(+s: String, +x: String) -> String:
  Bool.pick(String, String.contains(s, x), "yes", "no")

def state(+sid: String, +count: String) -> String:
  "{\"id\":\"1\",\"type\":\"response\",\"command\":\"get_state\",\"success\":true,\"data\":{\"thinkingLevel\":\"off\",\"isStreaming\":false,\"sessionId\":\"" ++ sid ++ "\",\"messageCount\":" ++ count ++ ",\"pendingMessageCount\":0}}"

def upd(+e: String) -> String:
  "{\"type\":\"message_update\",\"usage\":{\"input\":10,\"output\":5},\"assistantMessageEvent\":" ++ e ++ "}"

def ui(+rest: String) -> String:
  "{\"type\":\"extension_ui_request\",\"id\":\"u1\"," ++ rest ++ "}"

def main() -> IO(Unit):
  +a0 = A.Acp.new()
  +fresh = turn("")
  +old = turn("bp-t1-9-0")
  +gs1 = P.Pi.line(a0, fresh, state("bp-t1-5-0", "0"))
  +gs2 = P.Pi.line(a0, old, state("bp-t1-9-0", "5"))
  +gs3 = P.Pi.line(a0, old, state("bp-t1-9-0", "0"))
  +a1 = st(gs2)
  +pok = P.Pi.line(a1, old, "{\"id\":\"2\",\"type\":\"response\",\"command\":\"prompt\",\"success\":true,\"data\":{\"disposition\":\"started\"}}")
  +phand = P.Pi.line(a1, old, "{\"id\":\"2\",\"type\":\"response\",\"command\":\"prompt\",\"success\":true,\"data\":{\"disposition\":\"handled\"}}")
  +pkey = P.Pi.line(a1, old, "{\"id\":\"2\",\"type\":\"response\",\"command\":\"prompt\",\"success\":false,\"error\":\"No API key found for the selected model.\"}")
  +t1 = P.Pi.line(a1, old, upd("{\"type\":\"text_start\",\"contentIndex\":0}"))
  +t2 = P.Pi.line(st(t1), old, upd("{\"type\":\"text_delta\",\"contentIndex\":0,\"delta\":\"Let me check. \"}"))
  +t3 = P.Pi.line(st(t2), old, upd("{\"type\":\"text_start\",\"contentIndex\":2}"))
  +tsh = P.Pi.line(st(t2), old, "{\"type\":\"tool_execution_start\",\"toolCallId\":\"call_1\",\"toolName\":\"bash\",\"args\":{\"command\":\"echo hi > out.txt && cat out.txt\"}}")
  +trd = P.Pi.line(st(t2), old, "{\"type\":\"tool_execution_start\",\"toolCallId\":\"call_2\",\"toolName\":\"read\",\"args\":{\"path\":\"src/a.bend\"}}")
  +tbp = P.Pi.line(st(t2), old, "{\"type\":\"tool_execution_start\",\"toolCallId\":\"call_3\",\"toolName\":\"mcp__backplane__thread_list\",\"args\":{}}")
  +tend = P.Pi.line(st(t2), old, "{\"type\":\"tool_execution_end\",\"toolCallId\":\"call_1\",\"toolName\":\"bash\",\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"hi\\n\"}]},\"isError\":false,\"durationMs\":8}")
  +ok = P.Pi.line(st(t2), old, "{\"type\":\"agent_settled\",\"aborted\":false}")
  +e1 = P.Pi.line(a1, old, "{\"type\":\"message_end\",\"message\":{\"role\":\"assistant\",\"content\":[],\"stopReason\":\"error\",\"errorMessage\":\"Connection error.\"}}")
  +efail = P.Pi.line(st(e1), old, "{\"type\":\"agent_settled\",\"aborted\":false}")
  +e2 = P.Pi.line(st(e1), old, "{\"type\":\"message_end\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"ok\"}],\"stopReason\":\"stop\"}}")
  +eok = P.Pi.line(st(e2), old, "{\"type\":\"agent_settled\",\"aborted\":false}")
  +retry = P.Pi.line(a1, old, "{\"type\":\"auto_retry_start\",\"attempt\":1,\"maxAttempts\":3,\"delayMs\":2000,\"errorMessage\":\"Connection error.\"}")
  +skip = P.Pi.line(a1, old, "{\"type\":\"message_start\",\"message\":{\"role\":\"system\",\"content\":\"\"}}")
  +skip2 = P.Pi.line(a1, old, "{\"type\":\"message_end\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hello\"}]}}")
  +apr = P.Pi.line(a1, old, ui("\"method\":\"confirm\",\"title\":\"backplane:approval\",\"message\":\"{\\\"tool\\\":\\\"bash\\\",\\\"input\\\":{\\\"command\\\":\\\"rm -rf build\\\"}}\""))
  +afree = P.Pi.line(a1, turn.free("bp-t1-9-0"), ui("\"method\":\"confirm\",\"title\":\"backplane:approval\",\"message\":\"{\\\"tool\\\":\\\"bash\\\",\\\"input\\\":{\\\"command\\\":\\\"ls\\\"}}\""))
  +sel = P.Pi.line(a1, old, ui("\"method\":\"select\",\"title\":\"Which branch?\",\"options\":[\"main\",\"dev\"]"))
  +cnf = P.Pi.line(a1, old, ui("\"method\":\"confirm\",\"title\":\"Clear session?\",\"message\":\"All messages will be lost.\""))
  +warn = P.Pi.line(a1, old, ui("\"method\":\"notify\",\"message\":\"MCP server x failed\",\"notifyType\":\"warning\""))
  +info = P.Pi.line(a1, old, ui("\"method\":\"notify\",\"message\":\"hi\",\"notifyType\":\"info\""))
  +status = P.Pi.line(a1, old, ui("\"method\":\"setStatus\",\"statusKey\":\"k\",\"statusText\":\"x\""))
  do IO<Unit>:
    C.Check.str("pi init", P.Pi.init(), "{\"id\":\"1\",\"type\":\"get_state\"}")
    C.Check.str("pi fresh session id", P.Pi.session("", "t1", "1792-7"), "bp-t1-1792-7-0")
    C.Check.str("pi session kept", P.Pi.session("bp-t1-9-0", "t1", "1792-7"), "bp-t1-9-0")
    C.Check.str("pi session id safe", P.Pi.session("", "l~t1", "a b"), "bp-l-t1-a-b-0")
    C.Check.str("pi opened prompt", sends(gs1), "{\"id\":\"2\",\"type\":\"prompt\",\"message\":\"hello\"}")
    C.Check.str("pi opened started", emits(gs1), "{\"type\":\"thread.started\",\"thread_id\":\"bp-t1-5-0\"}")
    C.Check.str("pi resumed no notice", emits(gs2), "{\"type\":\"thread.started\",\"thread_id\":\"bp-t1-9-0\"}")
    C.Check.str("pi resumed empty notice", has(emits(gs3), "\"type\":\"notice\""), "yes")
    C.Check.str("pi resumed empty says context", has(emits(gs3), "without the earlier context"), "yes")
    C.Check.str("pi prompt accepted quiet", outs(pok), "")
    C.Check.str("pi prompt handled ends", has(outs(phand), "{\"type\":\"turn.completed\"}"), "yes")
    C.Check.str("pi no key fails with hint", outs(pkey), "{\"type\":\"turn.failed\",\"message\":\"No API key found for the selected model. (sign Pi in once: run `pi` and use /login, or set the provider's API key)\"}")
    C.Check.str("pi no key ends", done(st(pkey)), "done")
    C.Check.str("pi first text no break", outs(t1), "")
    C.Check.str("pi text streams", outs(t2), "{\"type\":\"item.delta\",\"text\":\"Let me check. \"}")
    C.Check.str("pi later text new paragraph", outs(t3), "{\"type\":\"item.delta\",\"text\":\"\\n\\n\"}")
    C.Check.str("pi shell named by command", outs(tsh), "{\"type\":\"item.completed\",\"item\":{\"type\":\"command_execution\",\"id\":\"call_1\",\"command\":\"echo hi > out.txt && cat out.txt\"}}")
    C.Check.str("pi read names file", has(outs(trd), "\"command\":\"read src/a.bend\""), "yes")
    C.Check.str("pi backplane tool named", has(outs(tbp), "\"command\":\"backplane thread_list\""), "yes")
    C.Check.str("pi tool done", outs(tend), "{\"type\":\"tool.done\",\"id\":\"call_1\"}")
    C.Check.str("pi settled reply", outs(ok), "{\"type\":\"item.completed\",\"item\":{\"type\":\"agent_message\",\"text\":\"Let me check. \"}} | {\"type\":\"turn.completed\"}")
    C.Check.str("pi settled ends", done(st(ok)), "done")
    C.Check.str("pi error kept quiet", outs(e1), "")
    C.Check.str("pi error fails turn", outs(efail), "{\"type\":\"turn.failed\",\"message\":\"Connection error.\"}")
    C.Check.str("pi retried success completes", has(outs(eok), "{\"type\":\"turn.completed\"}"), "yes")
    C.Check.str("pi retry said", has(outs(retry), "Pi is retrying (attempt 1 of 3): Connection error."), "yes")
    C.Check.str("pi system line skipped", outs(skip), "")
    C.Check.str("pi user line skipped", outs(skip2), "")
    C.Check.str("pi approval parks", has(asks(apr), "\"method\":\"bp/ask\""), "yes")
    C.Check.str("pi approval kind", has(asks(apr), "\"kind\":\"approval\",\"proto\":\"pi\",\"tool\":\"bash\",\"detail\":\"rm -rf build\""), "yes")
    C.Check.str("pi approval sends nothing", outs(apr), "")
    C.Check.str("pi approval accept", D.Dlg.reply(asks(apr), "accept"), "{\"type\":\"extension_ui_response\",\"id\":\"u1\",\"confirmed\":true}")
    C.Check.str("pi approval session", D.Dlg.reply(asks(apr), "session"), "{\"type\":\"extension_ui_response\",\"id\":\"u1\",\"confirmed\":true}")
    C.Check.str("pi approval decline", D.Dlg.reply(asks(apr), "decline"), "{\"type\":\"extension_ui_response\",\"id\":\"u1\",\"confirmed\":false}")
    C.Check.str("pi approval dismissed", D.Dlg.reply(asks(apr), ""), "{\"type\":\"extension_ui_response\",\"id\":\"u1\",\"confirmed\":false}")
    C.Check.str("pi full access allows", sends(afree), "{\"type\":\"extension_ui_response\",\"id\":\"u1\",\"confirmed\":true}")
    C.Check.str("pi full access no ask", asks(afree), "")
    C.Check.str("pi select is a question", has(asks(sel), "\"kind\":\"question\",\"proto\":\"pi\",\"tool\":\"Pi\",\"detail\":\"Which branch?\",\"options\":\"main\\ndev\""), "yes")
    C.Check.str("pi select answer", D.Dlg.reply(asks(sel), "dev"), "{\"type\":\"extension_ui_response\",\"id\":\"u1\",\"value\":\"dev\"}")
    C.Check.str("pi select dismissed", D.Dlg.reply(asks(sel), ""), "{\"type\":\"extension_ui_response\",\"id\":\"u1\",\"cancelled\":true}")
    C.Check.str("pi confirm question choices", has(asks(cnf), "\"options\":\"Yes\\nNo\",\"bool\":true"), "yes")
    C.Check.str("pi confirm question text", has(asks(cnf), "\"detail\":\"Clear session?\\n\\nAll messages will be lost.\""), "yes")
    C.Check.str("pi confirm yes", D.Dlg.reply(asks(cnf), "Yes"), "{\"type\":\"extension_ui_response\",\"id\":\"u1\",\"confirmed\":true}")
    C.Check.str("pi confirm no", D.Dlg.reply(asks(cnf), "No"), "{\"type\":\"extension_ui_response\",\"id\":\"u1\",\"confirmed\":false}")
    C.Check.str("pi warning said", outs(warn), "{\"type\":\"notice\",\"message\":\"Pi: MCP server x failed\"}")
    C.Check.str("pi info quiet", outs(info), "")
    C.Check.str("pi status ignored", outs(status), "")
    C.Check.str("pi extension gates by title", has(P.Pi.ext(), "ctx.ui.confirm('backplane:approval'"), "yes")
    C.Check.str("pi extension adds mcp", has(P.Pi.ext(), "pi.registerMcpServer('backplane'"), "yes")
