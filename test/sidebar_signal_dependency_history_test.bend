import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/signal.bend as G
import ../src/core/client.bend as U
import ../src/core/json.bend as J
import ../src/core/thin.bend as T
import ../src/core/thin-live.bend as L
import ../src/core/thin-pace.bend as P
import ../src/server/thin-signals.bend as K
import ../src/server/thin-actor.bend as A
import ../src/server/thin-view.bend as V


def state() -> M.State:
  M.State.replay([M.ProjectCreated{"p", "Board", "/tmp/signal-revision", 1n},
    M.ThreadCreated{"self", "p", "Here", M.Local{}, "", "", "codex", "", 2n},
    M.ThreadCreated{"other", "p", "Other", M.Local{}, "", "", "codex", "", 3n},
    M.TurnChanged{"other", M.Running{}, 4n}], M.State.empty())

def yes(b: Bool) -> String:
  Bool.pick(String, b, "yes", "no")

def same(+a: String, +b: String) -> String:
  yes(C.Check.same(a, b))

def ui(st: M.State, clock: Nat) -> U.Ui:
  U.Ui.info_set(U.Ui.scratch_set(U.Ui.flag_on(U.Ui.select.k(U.Ui.adopt.raw(U.Ui.init(clock), st), "self"), "settings"), "self", "PRIVATE 日本語 IME draft"), "local.mailroom", "on")

def request() -> J.Json:
  J.Json.obj([J.KV{"target", V.Target.json("thread", "self")}, J.KV{"action", J.Str{"flag"}}, J.KV{"value", J.Str{"settings"}}, J.KV{"signalRevision", J.Num{"0"}}])

def activity() -> M.Change:
  M.ActivityLogged{"self", "activity", "warn", "notice", "Visible synthetic warning", 12n}

def assistant() -> M.Change:
  M.MessagePosted{"self", "message", M.Assistant{}, "Visible synthetic assistant", 12n}

def stamp(+cs: List<&2, M.Change>) -> Nat:
  G.SignalRevision.advance(cs, M.State.seq(state()), M.State.seq(M.State.replay(cs, state())))

def rendered(r: A.Rendered) -> J.Json:
  match r:
    case A.Rendered{_, res}: res

def render_reply(+cs: List<&2, M.Change>) -> J.Json:
  +st = M.State.replay(cs, state())
  +u = U.Ui.online(ui(state(), 13n), True{})
  +action = V.Action.run(True{}, u, request(), 13n)
  +a = A.Actor.accept(A.Signals.save(True{}, A.Actor.make(u, "view", V.Target.json("thread", "self")), K.SignalCache.obtain("epoch", state(), None{})), action, False{})
  +index = T.Index.of(st)
  rendered(A.Actor.render.web.revision(a, action, st, index, request(), "epoch", 13n, T.Index.page(index, "self", 0n, 32n), L.Stream.blank(), stamp(cs)))

def equal_reply(+cs: List<&2, M.Change>) -> String:
  +st = M.State.replay(cs, state())
  +u = U.Ui.online(ui(state(), 13n), True{})
  +action = V.Action.run(True{}, u, request(), 13n)
  +a = A.Actor.accept(A.Actor.make(u, "view", V.Target.json("thread", "self")), action, False{})
  +index = T.Index.of(st)
  same(J.Json.show(render_reply(cs)), J.Json.show(rendered(A.Actor.render.web.fresh(a, action, st, index, request(), "epoch", 13n, T.Index.page(index, "self", 0n, 32n), L.Stream.blank()))))

# Match actual text nodes, avoiding a repeated substring walk over the full serialized reply.
def has_text(j: J.Json, +wanted: String) -> Bool:
  match j:
    case J.Str{text}: C.Check.same(text, wanted)
    case J.Arr{items}: has_text(items, wanted)
    case J.Obj{fields}: has_text(fields, wanted)
    case J.Item{head, tail}: Bool.or(has_text(head, wanted), has_text(tail, wanted))
    case J.Field{_, val, tail}: Bool.or(has_text(val, wanted), has_text(tail, wanted))
    case _: False{}

def pending() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("fresh warning body remains visible", yes(has_text(render_reply([activity()]), "Visible synthetic warning")), "yes")
    C.Check.str("fresh assistant complete reply equals uncached", equal_reply([assistant()]), "yes")
    C.Check.str("fresh assistant body remains visible", yes(has_text(render_reply([assistant()]), "Visible synthetic assistant")), "yes")
    C.Check.str("fresh approval full reply equals uncached", equal_reply([M.AskOpened{"a", "other", "approval", "tool", "Allow", "", 12n}]), "yes")
    C.Check.str("new epoch cannot reuse dependency memo", yes(K.SignalCache.hit(K.SignalCache.obtain("epoch", state(), None{}), "new-epoch", M.State.seq(state()))), "no")

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("fresh warning complete reply equals uncached", equal_reply([activity()]), "yes")
    pending()
