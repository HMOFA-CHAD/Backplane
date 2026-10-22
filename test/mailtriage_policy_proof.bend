import Base
import ../src/core/hub.bend as H
import ../src/core/model.bend as M

# These universal claims are also in LAWS/PROOF; this bounded check times
# their production import closure without starting the shared full gate.
def duplicate_quiet(s: M.State, now: Nat, bot: String, conv: String, text: String, input: String) ->
  {H.Run.triage.send(False{}, s, now, bot, conv, text, input) == H.Step.none() : H.Step}: {==}

def unknown_run_quiet(s: M.State, now: Nat, bot: String, conv: String, text: String) ->
  {H.Run.triage.got(None{}, s, now, bot, conv, text) == H.Step.none() : H.Step}: {==}
