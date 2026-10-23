import Base
import ./check.bend as C
import ../src/server/thin-actor.bend as TA
import ../src/server/thin-view.bend as V
import ../src/core/client.bend as U
import ../src/core/model.bend as M
import ../src/core/json.bend as J

def state() -> M.State:
  M.State.replay([
    M.ProjectCreated{"p1", "Board", "/tmp/board", 1n},
    M.ThreadCreated{"self", "p1", "Here", M.Local{}, "", "", "codex", "", 2n},
    M.ThreadCreated{"t100-7", "p1", "Fix perf", M.Local{}, "", "", "codex", "", 3n},
    M.ThreadCreated{"bot-thread", "p1", "Bot chat", M.Local{}, "", "", "codex", "", 4n},
    M.BotSet{"miso", "Miso", "bot-thread", 0n, "Parts helper", 5n},
    M.RoomSet{"room", "Hardware", "miso", 6n}], M.State.empty())

def request(+draft: String) -> J.Json:
  J.Json.obj([J.KV{"target", V.Target.json("thread", "self")}, J.KV{"session", J.Json.obj([
    J.KV{"sel", J.Str{"self"}}, J.KV{"rid", J.Num{"100"}},
    J.KV{"drafts", J.Json.obj([J.KV{"self", J.Str{draft}}, J.KV{"other", J.Str{"PRIVATE_OTHER"}}, J.KV{"@f.secret", J.Str{"PRIVATE_FIELD"}}])},
    J.KV{"info", J.Json.obj([J.KV{"refs", J.Str{"@FORGED"}}, J.KV{"refs.for", J.Str{"self\n@mi"}}])}])}])

def fresh(+draft: String) -> TA.Actor:
  TA.Actor.refresh(Nil{}, True{}, state(), J.Json.obj(Nil{}), J.Json.obj(Nil{}), 10n, request(draft), "view")

def refresh(+a: TA.Actor, +draft: String) -> TA.Actor:
  TA.Actor.refresh([a], True{}, state(), J.Json.obj(Nil{}), J.Json.obj(Nil{}), 11n, request(draft), "view")

def act(+a: TA.Actor, +action: String, +value: String) -> TA.Actor:
  TA.Actor.accept(a, V.Action.run(True{}, TA.Actor.ui(a), J.Json.obj([
    J.KV{"action", J.Str{action}}, J.KV{"value", J.Str{value}}]), 11n), False{})

def rows(rs: List<&2, U.SkillRow>) -> String:
  match rs:
    case Nil{}: ""
    case U.SkillRow{n, _, _} <> tail: n ++ "," ++ rows(tail)

def offered(+a: TA.Actor) -> String:
  rows(U.Ui.skills(TA.Actor.ui(a)))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("thin saved bot token hydrates authoritative suggestions", offered(fresh("ask @mi")), "@Miso,")
    C.Check.str("thin thread token hydrates after draft update", offered(refresh(fresh("plain"), "see >fi")), ">fix-perf,")
    C.Check.str("thin project token hydrates", offered(fresh("in %bo")), "%board,")
    C.Check.str("thin room token hydrates", offered(fresh("in #ha")), "#hardware,")
    C.Check.str("thin plain words offer no references", offered(refresh(fresh("@mi"), "literal text")), "")
    C.Check.str("thin Escape stays closed across unchanged refresh", offered(refresh(act(fresh("ask @mi"), "skill-close", ""), "ask @mi")), "")
    C.Check.str("thin edit reopens Escape dismissal even after returning to same text", offered(refresh(refresh(act(fresh("ask @mi"), "skill-close", ""), "ask @mis"), "ask @mi")), "@Miso,")
    C.Check.str("thin completion uses existing insertion", U.Ui.draft_text(TA.Actor.ui(act(fresh("日本語 @mi"), "skill", ""))), "日本語 @Miso ")
    C.Check.str("thin hydration preserves prefix and literal token", U.Ui.draft_text(TA.Actor.ui(refresh(fresh("plain"), "日本語 >fi"))), "日本語 >fi")
    C.Check.str("thin other-thread draft rejected", U.Ui.scratch(TA.Actor.ui(fresh("@mi")), "other"), "")
    C.Check.str("thin private form draft rejected", U.Ui.scratch(TA.Actor.ui(fresh("@mi")), "@f.secret"), "")
    C.Check.str("thin hydration does not allocate RPC IDs", Nat.show(U.Ui.rid(TA.Actor.ui(refresh(fresh("plain"), "@mi")))), "100")
