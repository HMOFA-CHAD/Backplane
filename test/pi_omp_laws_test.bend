import Base
import ./check.bend as C
import ../src/core/hub.bend as H
import ../src/core/model.bend as M
import ../src/core/agent.bend as AG
import ../src/core/pi.bend as PIA
import ../src/core/omp.bend as OMPA
import ../src/core/dialog.bend as DLG

# Exactly the eighteen newly appended laws; previous laws remain untouched.
# This is a focused proof entry point, not the full PROOF.bend gate.

# -------------------------------------------------------

# a Pi thread's turn is one run of `pi --mode rpc`; an Oh My Pi thread's
# one of `omp acp` (two protocols, two Outs)
law pi_run_turn:
  for +th: String
  for +cwd: String
  for +m: String
  for +s: String
  for +r: M.RuntimeMode
  for i: M.InteractionMode
  for +t: String
  for u: String
  {H.Hub.run.k(6n, th, cwd, "pi", m, s, r, i, t, u) == [H.PiTurn{th, cwd, m, s, r, t}] : List<&2, H.Out>}

law omp_run_turn:
  for +th: String
  for +cwd: String
  for +m: String
  for +s: String
  for +r: M.RuntimeMode
  for i: M.InteractionMode
  for +t: String
  for u: String
  {H.Hub.run.k(7n, th, cwd, "omp", m, s, r, i, t, u) == [H.OmpTurn{th, cwd, m, s, r, t}] : List<&2, H.Out>}

# Stop ends either's process
law interrupt_pi_stops:
  for +th: String
  for r: String
  {H.Stop.outs("pi", th, r) == [H.AgentStop{th}] : List<&2, H.Out>}

law interrupt_omp_stops:
  for +th: String
  for r: String
  {H.Stop.outs("omp", th, r) == [H.AgentStop{th}] : List<&2, H.Out>}

# their tool calls are logged before they run: design steps come at
# "tool.done"
law pi_acp_like:
  {H.Hub.acp_like("pi") == True{} : Bool}

law omp_acp_like:
  {H.Hub.acp_like("omp") == True{} : Bool}

# supervision: supervised asks, accept edits asks for all but edits, full
# access asks nothing
law pi_mode_supervised_asks:
  {PIA.Pi.mode.k(0n) == "ask" : String}

law pi_mode_accept_edits:
  {PIA.Pi.mode.k(1n) == "edit" : String}

law pi_mode_full_allows:
  {PIA.Pi.mode.k(3n) == "allow" : String}

law omp_mode_supervised_asks:
  {OMPA.Omp.mode.k(0n) == "always-ask" : String}

law omp_mode_accept_edits:
  {OMPA.Omp.mode.k(1n) == "write" : String}

law omp_mode_full_allows:
  {OMPA.Omp.mode.k(3n) == "yolo" : String}

# a Pi thread's later turns open its own session, never a new one
law pi_session_kept:
  for +th: String
  for +g: String
  {PIA.Pi.session("bp-t1-9-0", th, g) == "bp-t1-9-0" : String}

# only an allow answers yes: a declined or dismissed approval never runs
# the tool
law dialog_decline_denies:
  {DLG.Dlg.allows("decline") == False{} : Bool}

law dialog_dismissed_denies:
  {DLG.Dlg.allows("") == False{} : Bool}

law dialog_session_allows:
  {DLG.Dlg.allows("session") == True{} : Bool}

# Pi's thinking level goes as --thinking; one Pi does not take, nowhere
law pi_effort_flag:
  {AG.Effort.args("pi", "high") == ["--thinking", "high"] : List<&2, String>}

law pi_effort_unknown_default:
  {AG.Effort.args("pi", "turbo") == Nil{} : List<&2, String>}


def pi_run_turn(th, cwd, m, s, r, i, t, u): {==}
def omp_run_turn(th, cwd, m, s, r, i, t, u): {==}
def interrupt_pi_stops(th, r): {==}
def interrupt_omp_stops(th, r): {==}
def pi_acp_like(): {==}
def omp_acp_like(): {==}
def pi_mode_supervised_asks(): {==}
def pi_mode_accept_edits(): {==}
def pi_mode_full_allows(): {==}
def omp_mode_supervised_asks(): {==}
def omp_mode_accept_edits(): {==}
def omp_mode_full_allows(): {==}
def pi_session_kept(th, g): {==}
def dialog_decline_denies(): {==}
def dialog_dismissed_denies(): {==}
def dialog_session_allows(): {==}
def pi_effort_flag(): {==}
def pi_effort_unknown_default(): {==}


def main() -> IO(Unit):
  C.Check.str("eighteen new Pi/OMP laws typecheck", "proved", "proved")
