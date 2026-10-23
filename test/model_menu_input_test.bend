import Base
import ./check.bend as C
import ../src/server/thin-actor.bend as A
import ../src/server/thin-view.bend as V
import ../src/core/model.bend as M
import ../src/core/client.bend as U
import ../src/core/json.bend as J
import ../src/core/thin.bend as T
import ../src/core/thin-live.bend as L

def st(provider: String) -> M.State:
  M.State.replay([M.ProjectCreated{"p", "Board", "/tmp/menu", 1n}, M.ThreadCreated{"self", "p", "Here", M.Local{}, "", "", provider, "", 2n}], M.State.empty())

def p(opt: Bool, action: String, value: String) -> J.Json:
  J.Json.obj([J.KV{"target", V.Target.json("thread", "self")}, J.KV{"session", J.Json.obj([
    J.KV{"sel", J.Str{"self"}}, J.KV{"rid", J.Num{"100"}}, J.KV{"open", J.Json.obj([J.KV{"models", J.Flag{False{}}}])}])},
    J.KV{"action", J.Str{action}}, J.KV{"value", J.Str{value}}, J.KV{"modelMenuInput", J.Flag{opt}}])

def warm(+a: A.Actor) -> A.Actor:
  +u = A.Actor.ui(a)
  A.Actor.accept(a, V.ActResult{U.Ui.scratch_set(u, "@fab.at", U.Fab.at(u)), Nil{}}, False{})

# An existing conversation has completed its independent project-card read.
# A cold first action must still fall back when it has that extra command.
def run(+provider: String, opt: Bool) -> A.Rendered:
  +request = p(opt, "flag", "models")
  A.Actor.render(warm(A.Actor.refresh(Nil{}, True{}, st(provider), J.Json.obj(Nil{}), J.Json.obj(Nil{}), 10n, request, "view")), True{}, st(provider), T.Index.empty(), request, "epoch", 10n, Nil{}, L.Stream.blank())

def cold() -> A.Rendered:
  +request = p(True{}, "flag", "models")
  A.Actor.render(A.Actor.refresh(Nil{}, True{}, st("codex"), J.Json.obj(Nil{}), J.Json.obj(Nil{}), 10n, request, "view"), True{}, st("codex"), T.Index.empty(), request, "epoch", 10n, Nil{}, L.Stream.blank())

def result(+r: A.Rendered) -> J.Json:
  match r:
    case A.Rendered{_, value}: value

def actor(+r: A.Rendered) -> A.Actor:
  match r:
    case A.Rendered{a, _}: a

def yes(b: Bool) -> String:
  Bool.pick(String, b, "yes", "no")

def has(+j: J.Json, key: String) -> Bool:
  Maybe.is_some(&2, J.Json, J.Json.get(j, key))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("model toggle opts into compact actor result", yes(J.Json.get_bool(result(run("codex", True{})), "modelMenuInput", False{})), "yes")
    C.Check.str("compact actor opens normal models flag", yes(U.Ui.flag(A.Actor.ui(actor(run("codex", True{}))), "models")), "yes")
    C.Check.str("compact ACK has no conversation picture", yes(has(result(run("codex", True{})), "shown")), "no")
    C.Check.str("compact ACK has no window cursor", yes(has(result(run("codex", True{})), "window")), "no")
    C.Check.str("old client retains full result", yes(has(result(run("codex", False{})), "shown")), "yes")
    C.Check.str("cold project-card command retains full result", yes(has(result(cold()), "shown")), "yes")
    C.Check.str("native renderer cannot request compact model result", yes(A.ModelMenu.request(False{}, p(True{}, "flag", "models"))), "no")
    C.Check.str("model choice stays normal action", yes(A.ModelMenu.request(True{}, p(True{}, "model", "choice"))), "no")
    C.Check.str("other flag stays normal action", yes(A.ModelMenu.request(True{}, p(True{}, "flag", "settings"))), "no")
    C.Check.str("opencode retains model refresh exactly once", Nat.show(List.length(&2, J.Json, J.Json.elems(J.Json.get_obj(result(run("opencode", True{})), "cmds")))), "2")
    C.Check.str("compact result never becomes memo picture", Nat.show(List.length(&2, A.Memo, A.Actor.memos([actor(A.Rendered.remember(run("codex", True{}), "key", 1n, L.Stream.blank()))]))), "0")
