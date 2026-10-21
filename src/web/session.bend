import Base
import ../core/json.bend as J
import ../core/model.bend as M
import ../core/client.bend as U
import ../core/presentation.bend as P
import ../core/msgs.bend as MSG
import ./app.bend as A

# Pure normal-web adapter for the shared authenticated presentation session.
# The server supplies current state. This adapter never executes commands or
# accepts serialized client state.
def WebSession.input(st: M.State, info: J.Json, live: J.Json, now: Nat, cid: String, session: J.Json) -> U.Ui:
  U.Ui.scratch_set(A.stamp(P.Session.input(st, info, live, now, cid, session)), "@presentation", "1")

# Only the current conversation's ordinary interactions are available before
# replay. Browser, Mailroom, settings and other controls are refused now; no
# deferred operation is queued to fire when history finishes.
def WebSession.allowed(action: String) -> Bool:
  A.presentation_allowed(action)

def WebSession.act.ready(allowed: Bool, +u: U.Ui, action: String, value: String) -> U.Act:
  match allowed:
    case True{}: A.act(u, action, value)
    case False{}: U.Act{U.Ui.error_set(u, MSG.T.viewer.loading(U.Lang.loc(u))), Nil{}}

def WebSession.act(u: U.Ui, +action: String, value: String) -> U.Act:
  WebSession.act.ready(WebSession.allowed(action), u, action, value)

# Commands are UNISSUED ordinary RPC/local instructions from the pure action.
# The host consumes a matching generation/request response once; duplicate or
# retired responses cannot issue commands. The server never also executes them.
def WebSession.result(+u: U.Ui, commands: J.Json, revision: Nat) -> J.Json:
  J.Json.obj([J.KV{"frontend", J.Json.nat(1n)}, J.KV{"web", J.Json.nat(1n)}, J.KV{"session", P.Session.pack(u)},
    J.KV{"view", A.presentation_view(U.Ui.scratch_set(u, "@presentation", "1"))}, J.KV{"cmds", commands}, J.KV{"revision", J.Json.nat(revision)}])
