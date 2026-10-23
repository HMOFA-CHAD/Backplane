import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/hub.bend as H
import ../src/core/mcp.bend as MC
import ../src/core/json.bend as J
import ../src/core/dialog.bend as D
import ../src/core/acp.bend as A
import ../src/core/msp.bend as S
import ../src/core/opencode.bend as O

def obj(line: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(line), J.Null{})

def base() -> M.State:
  M.State.replay([M.ProjectCreated{"p", "Synthetic", "/tmp/p", 1n},
    M.ThreadCreated{"pi", "p", "Pi", M.Local{}, "", "", "pi", "", 2n},
    M.ThreadCreated{"other", "p", "Other", M.Local{}, "", "", "omp", "", 2n}], M.State.empty())

def grant() -> M.State:
  M.State.replay([M.AskOpened{"allowed", "pi", "approval", "bash", "Synthetic command", "", 3n}, M.AskClosed{"allowed", "session", 4n}], base())

def approval() -> String:
  D.Dlg.line(J.Num{"1"}, "approval", "pi", [J.KV{"tool", J.Str{"bash"}}, J.KV{"detail", J.Str{"Synthetic command"}}])

def question() -> String:
  D.Dlg.line(J.Num{"2"}, "question", "elicit", [J.KV{"tool", J.Str{"Oh My Pi"}}, J.KV{"detail", J.Str{"Choose colour"}}, J.KV{"options", J.Str{"Red\nBlue"}}, J.KV{"key", J.Str{"q0"}}])

def call(s: M.State, th: String, line: String) -> MC.McpOut:
  MC.Mcp.handle(s, 10n, th, J.Null{}, "synthetic", obj(line))

def opened.cs(cs: List<&2, M.Change>) -> String:
  match cs:
    case Nil{}: ""
    case M.AskOpened{_, th, kind, tool, detail, options, _} <> rest:
      th ++ "|" ++ kind ++ "|" ++ tool ++ "|" ++ detail ++ "|" ++ options
    case _ <> rest: opened.cs(rest)

def opened(o: MC.McpOut) -> String:
  match o:
    case MC.McpOut{_, H.Step{cs, _}, _}: opened.cs(cs)

def reply(o: MC.McpOut) -> String:
  match o:
    case MC.McpOut{r, _, _}: r

def state.out(o: A.AcpOut) -> String:
  match o:
    case A.AcpOut{_, send, emit, _}: String.join(List.append(&2, String, send, emit), "|")

def oc.turn() -> O.OcpTurn:
  O.OcpTurn{A.AcpTurn{"/tmp/p", "", "instructions", "hello", "", True{}}, "provider/picked"}

def oc.reply() -> String:
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"sessionId\":\"S\"}}"

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("Pi actual MCP dispatch opens owned approval", opened(call(base(), "pi", approval())), "pi|approval|bash|Synthetic command|")
    C.Check.str("Pi session grant answers in its own protocol", reply(call(grant(), "pi", approval())), "{\"type\":\"extension_ui_response\",\"id\":1,\"confirmed\":true}")
    C.Check.str("Pi permission cannot borrow another thread grant", opened(call(grant(), "other", approval())), "other|approval|bash|Synthetic command|")
    C.Check.str("OMP actual MCP dispatch opens real question with choices", opened(call(base(), "other", question())), "other|input|Oh My Pi|Choose colour|Red\nBlue")
    C.Check.str("parked Pi decline remains denial through MCP reply", MC.Mcp.permission.reply(approval(), "decline"), "{\"type\":\"extension_ui_response\",\"id\":1,\"confirmed\":false}")
    C.Check.str("existing Grok permission dispatcher preserved", Bool.show(String.eq(opened(call(base(), "pi", "{\"id\":3,\"method\":\"session/request_permission\",\"params\":{}}")), opened(MC.Grok.permit(base(), 10n, "pi", obj("{\"id\":3,\"method\":\"session/request_permission\",\"params\":{}}"))))), "True")
    C.Check.str("existing Muse permission dispatcher preserved", Bool.show(String.eq(opened(call(base(), "pi", "{\"id\":4,\"method\":\"approval/request\",\"params\":{}}")), opened(MC.Muse.permit(base(), 10n, "pi", obj("{\"id\":4,\"method\":\"approval/request\",\"params\":{}}"))))), "True")
    C.Check.str("existing OpenCode selected-model protocol dispatch preserved", Bool.show(Bool.and(String.eq(state.out(S.Proto.line(A.Acp.new(), S.POc{oc.turn()}, oc.reply())), state.out(O.Ocp.line(A.Acp.new(), oc.turn(), oc.reply()))), String.contains(state.out(S.Proto.line(A.Acp.new(), S.POc{oc.turn()}, oc.reply())), "session/set_config_option"))), "True")
