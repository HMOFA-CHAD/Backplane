import Base
import ./check.bend as C
import ../src/server/thin-actor.bend as TA
import ../src/server/thin-view.bend as V
import ../src/core/client.bend as U
import ../src/core/model.bend as M
import ../src/core/json.bend as J
import ../src/core/teach.bend as TE

# The integration owner runs only this changed ownership behavior. No IO,
# native window, providers, or user state participates in these cases.
def state() -> M.State:
  M.State.replay([M.ThreadCreated{"review", "", "Review", M.Local{}, "", "", "codex", "", 1n}], M.State.empty())

def request() -> J.Json:
  J.Json.obj([J.KV{"target", V.Target.json("thread", "review")}, J.KV{"session", J.Json.obj([J.KV{"rid", J.Num{"100"}}])}])

def refresh(+actors: List<&2, TA.Actor>, +teach: TE.TeachSt) -> TA.Actor:
  TA.Actor.refresh(actors, True{}, state(), J.Json.obj(TE.Teach.info(teach)), J.Json.obj(Nil{}), 2n, request(), "browser-view")

def retained(a: TA.Actor) -> TA.Actor:
  match a:
    case TA.Actor{u, view, target, pending, reads, dirty, memo}:
      TA.Actor{U.Ui.info_set(U.Ui.info_set(U.Ui.scratch_set(u, "@terminal.owner", "review"), "fold:steps", "1"), "local.mailroom", "on"), view, target, pending, reads, dirty, memo}

def main() -> IO(Unit):
  do IO<Unit>:
    +taken : TE.TeachBot = TE.Teach.takeover(TE.Teach.blank("review"))
    +owned : TE.TeachSt = TE.Teach.put(TE.Teach.empty(), taken)
    +actor : TA.Actor = retained(refresh(Nil{}, owned))
    C.Check.str("canonical takeover reaches actor", U.Teach.drive(TA.Actor.ui(actor), "review"), "takeover")
    +idle : TE.TeachSt = TE.Teach.put(owned, TE.Teach.handback(taken))
    C.Check.str("canonical idle ownership omits old owner", Nat.show(List.length(&2, J.KV, TE.Teach.info(idle))), "0")
    +back : TA.Actor = refresh([actor], idle)
    C.Check.str("handback clears omitted cached ownership", Bool.show(U.Teach.input(TA.Actor.ui(back), "review")), "False")
    C.Check.str("handback preserves fold preference", U.Ui.info(TA.Actor.ui(back), "fold:steps"), "1")
    C.Check.str("handback preserves unrelated mail actor info", U.Ui.info(TA.Actor.ui(back), "local.mailroom"), "on")
    C.Check.str("handback preserves terminal scratch owner", U.Ui.scratch(TA.Actor.ui(back), "@terminal.owner"), "review")
    +other : TA.Actor = refresh([actor], TE.Teach.put(TE.Teach.empty(), TE.Teach.takeover(TE.Teach.blank("other"))))
    C.Check.str("other canonical owner does not preserve stale selected owner", U.Teach.drive(TA.Actor.ui(other), "review"), "")
    C.Check.str("other canonical owner stays person-owned", U.Teach.drive(TA.Actor.ui(other), "other"), "takeover")
    C.Check.str("new takeover after handback reinstalls canonical ownership", U.Teach.drive(TA.Actor.ui(refresh([back], owned)), "review"), "takeover")
