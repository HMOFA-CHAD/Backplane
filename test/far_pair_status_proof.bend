import Base
import ../src/core/model.bend as M
import ../src/core/hub.bend as H
import ../src/core/mcp.bend as MC
import ../src/core/json.bend as J
import ../src/core/tailnet.bend as TN

# Exact copies of the new global statements, isolated from the existing late-import blocker.

law mcp_phase_monitoring:
  {M.Phase.name(MC.Mcp.phase(H.Answer.demo(True{}), M.State.thread.get(H.Answer.demo(True{}), "t1"))) == "monitoring" : String}

def mcp_phase_monitoring(): {==}

law mcp_phase_complete:
  {M.Phase.name(MC.Mcp.phase(H.Answer.demo(False{}), M.State.thread.get(H.Answer.demo(False{}), "t1"))) == "complete" : String}

def mcp_phase_complete(): {==}

law wake_says_killed:
  {H.Wake.text(False{}, H.Answer.demo(True{}), "t1", J.Json.obj([J.KV{"task_id", J.Str{"a"}}, J.KV{"status", J.Str{"killed"}}])) == "Woken: background work (killed)" : String}

def wake_says_killed(): {==}

law wake_completed_plain:
  {H.Wake.text(False{}, H.Answer.demo(True{}), "t1", J.Json.obj([J.KV{"task_id", J.Str{"a"}}, J.KV{"status", J.Str{"completed"}}])) == "Woken: background work" : String}

def wake_completed_plain(): {==}

law tailnet_announce_off:
  {[TN.Tailnet.announce(True{}, "http://100.64.0.1:3787"), TN.Tailnet.announce(False{}, "http://100.64.0.1:3787")] == ["http://100.64.0.1:3787", ""] : List<&2, String>}

def tailnet_announce_off(): {==}
