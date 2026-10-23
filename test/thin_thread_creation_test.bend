import Base
import ./check.bend as C
import ../src/server/thin-actor.bend as TA
import ../src/server/thin-view.bend as V
import ../src/core/client.bend as U
import ../src/core/model.bend as M
import ../src/core/json.bend as J

# Source-only regression for the hierarchy helper's post-create timeout.
# The sole integration owner runs it; no providers, browser or filesystem.
def state(+child: Bool) -> M.State:
  M.State.replay(List.append(&2, M.Change,
    [M.ProjectCreated{"p", "Project", "/tmp/project", 1n},
     M.ThreadCreated{"parent", "p", "Parent", M.Local{}, "", "/tmp/project", "codex", "", 1n},
     M.ThreadCreated{"other", "p", "Other", M.Local{}, "", "/tmp/project", "codex", "", 1n}],
    Bool.pick(List<&2, M.Change>, child,
      [M.ThreadCreated{"child", "p", "New subthread", M.Local{}, "", "/tmp/project", "codex", "", 2n},
       M.ThreadParentSet{"child", "parent", 2n}], Nil{})), M.State.empty())

def request(+id: String) -> J.Json:
  J.Json.obj([J.KV{"target", V.Target.json("thread", id)},
    J.KV{"session", J.Json.obj([J.KV{"rid", J.Num{"100"}}])}])

def refresh(+a: TA.Actor, +child: Bool, +view: String) -> TA.Actor:
  TA.Actor.refresh([a], True{}, state(child), J.Json.obj(Nil{}), J.Json.obj(Nil{}), 3n, request("parent"), view)

def navigate(+a: TA.Actor) -> TA.Actor:
  TA.Actor.refresh([a], True{}, state(True{}), J.Json.obj(Nil{}), J.Json.obj(Nil{}), 3n, request("other"), "original-view")

def created(+child: Bool) -> TA.Actor:
  +a = TA.Actor.refresh(Nil{}, True{}, state(child), J.Json.obj(Nil{}), J.Json.obj(Nil{}), 2n, request("parent"), "original-view")
  TA.Actor.accept(a, V.Action.run(True{}, TA.Actor.ui(a), J.Json.obj([
    J.KV{"action", J.Str{"thread-child"}}, J.KV{"value", J.Str{"parent"}}]), 2n), False{})

def acknowledged(+a: TA.Actor) -> TA.Actor:
  TA.Actor.reply(a, True{}, "", U.Made.demo(U.Ui.scratch(TA.Actor.ui(a), "@want.new"), "child"))

def selected(+a: TA.Actor) -> String:
  J.Json.get_str(V.Target.after(TA.Actor.ui(a)), "id", "")

def main() -> IO(Unit):
  do IO<Unit>:
    +early : TA.Actor = acknowledged(created(False{}))
    C.Check.str("ACK waits while child is absent from actor state", selected(early), "parent")
    C.Check.str("refresh resolves retained creation after installing child", selected(refresh(early, True{}, "original-view")), "child")
    +ready : TA.Actor = acknowledged(created(True{}))
    C.Check.str("ACK selects child already installed in actor", selected(ready), "child")
    C.Check.str("same view refresh preserves acknowledged selection", selected(refresh(ready, True{}, "original-view")), "child")
    +navigated : TA.Actor = refresh(early, True{}, "replacement-view")
    C.Check.str("explicit replacement view retires pending selection", selected(navigated), "parent")
    C.Check.str("retired selection cannot resolve on later update", selected(refresh(navigated, True{}, "replacement-view")), "parent")
    +different : TA.Actor = navigate(early)
    C.Check.str("different target retires pending selection even with same view", selected(different), "other")
    C.Check.str("different target cannot later resolve old pending child", selected(navigate(different)), "other")
    +requested : TA.Actor = created(False{})
    +late : TA.Actor = refresh(requested, True{}, "replacement-view")
    C.Check.str("old creation ACK cannot redirect replacement view", selected(TA.Actor.reply(late, True{}, "",
      U.Made.demo(U.Ui.scratch(TA.Actor.ui(requested), "@want.new"), "child"))), "parent")
