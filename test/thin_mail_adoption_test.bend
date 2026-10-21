import Base
import ./check.bend as C
import ./thin_mail_actor_fixture.bend as F
import ../src/server/thin-mail.bend as TM
import ../src/server/thin-actor.bend as TA
import ../src/core/client.bend as U
import ../src/core/model.bend as M
import ../src/core/mail.bend as ML
import ../src/core/mailview.bend as MV
import ../src/core/hub.bend as B
import ../src/core/json.bend as J

# Canonical fixture uses the actual legacy OFF-room events and typed RPC.
def changes() -> List<&2, M.Change>:
  [M.RoomPosted{"p1", "ra", "Alpha", "日本語 é🙂", 0n, 2n},
   M.ConvSet{"act-c", "Action", "pair", "person\nbot:ba\nbot:bb", "project", "", 3n},
   M.MailPosted{"m1", "act-c", "person", "bot:ba", "thread", "", "act", "Do it", 5n, 4n}]

def state() -> M.State:
  M.State.replay(changes(), F.state())

def adopted(+st: M.State) -> TA.Actor:
  TA.Actor.refresh(Nil{}, True{}, st, F.info(), F.obj("{}"), 100n, F.request("ba", 100n), "view-a")

def cold(+st: M.State) -> TA.Actor:
  TA.Actor.mail_cache(adopted(st), Nil{}, TM.Cache.of(st))

def refresh(+old: TA.Actor, +st: M.State, cache: TM.Cache) -> TA.Actor:
  TA.Actor.mail_cache(TA.Actor.refresh([old], True{}, st, F.info(), F.obj("{}"), 101n, F.request("ba", 100n), "view-a"), [old], cache)

def order(+u: U.Ui, +bot: String, +status: String, +project: String) -> String:
  String.join(ML.Order.slice(U.Mailv.index.order(U.Mailv.index(u), U.Mailv.index.key(bot, status, project)), 0n, 20n), ",")

def rows(xs: List<&2, MV.Row>) -> String:
  match xs:
    case Nil{}: ""
    case r <> tail: MV.Row.id(r) ++ "," ++ rows(tail)

def list_reply(+a: TA.Actor) -> TA.Actor:
  +rpc = F.find(TA.Actor.queued(a), "mail.list")
  TA.Actor.reply(TA.Actor.clean(a), True{}, "public-hub", F.reply(J.Json.as_raw(J.Json.get(rpc, "id"), ""), True{}, B.Mail.list(U.Ui.state(TA.Actor.ui(a)), J.Json.get_obj(rpc, "p"))))

def listed(+a: TA.Actor) -> String:
  rows(MV.Mv.page_of(U.Mailv.cache(TA.Actor.ui(a)), U.Mailv.key(TA.Actor.ui(a)), 0n))

def equal(+label: String, +a: U.Ui, +b: U.Ui) -> IO(Unit):
  do IO<Unit>:
    C.Check.str(label ++ " aggregate", order(a, "*", "", ""), order(b, "*", "", ""))
    C.Check.str(label ++ " FYI", order(a, "*", "fyi", ""), order(b, "*", "fyi", ""))
    C.Check.str(label ++ " Act", order(a, "*", "act", ""), order(b, "*", "act", ""))
    C.Check.str(label ++ " project", order(a, "*", "", "project"), order(b, "*", "", "project"))
    C.Check.str(label ++ " removed member", order(a, "bb", "", ""), order(b, "bb", "", ""))
    C.Check.str(label ++ " aggregate marks", order(a, "*", "done", ""), order(b, "*", "done", ""))

def main() -> IO(Unit):
  do IO<Unit>:
    +st : M.State = state()
    +cache : TM.Cache = TM.Cache.of(st)
    +a : TA.Actor = cold(st)
    +folded : U.Ui = U.Ui.fold(changes(), U.Ui.fold([M.ThreadCreated{"a", "", "Public A", M.Local{}, "", "", "codex", "", 1n},
      M.ThreadCreated{"b", "", "Public B", M.Local{}, "", "", "codex", "", 1n}, M.BotSet{"ba", "Alpha", "a", 0n, "", 1n}, M.BotSet{"bb", "Beta", "b", 0n, "", 1n},
      M.UberSet{"ba", "public-uber", 1n}, M.SettingSet{"mail.on", "off", 1n}, M.RoomSet{"ra", "Public room A", "ba", 1n}, M.RoomSet{"rb", "Public room B", "bb", 1n}], U.Ui.init(100n)))
    C.Check.str("canonical RPC has real OFF room before projection", Nat.show(J.Json.get_nat(B.Mail.list(st, F.obj("{\"bot\":\"*\"}")), "total", 0n)), "3")
    equal("cold adoption matches true canonical fold", TA.Actor.ui(a), folded)
    +ready : TA.Actor = TA.Actor.mail_ready(a)
    C.Check.str("cold actor queues internal readonly list", F.methods(TA.Actor.queued(ready)), "mail.list|")
    +done : TA.Actor = list_reply(ready)
    C.Check.str("successful canonical reply retains all aggregate rows", listed(done), "act-c,room:ra,room:rb,")
    C.Check.str("successful canonical reply retains nonzero total", Nat.show(MV.Mv.total(U.Mailv.cache(TA.Actor.ui(done)), U.Mailv.key(TA.Actor.ui(done)))), "3")
    C.Check.str("read reply never creates a durable send", Bool.show(F.only_reads(TA.Actor.queued(done))), "True")
    +drafted : TA.Actor = F.with_ui(done, U.Ui.scratch_set(U.Ui.scratch_set(TA.Actor.ui(done), "@f.mrreply", "private draft 🙂"), "@mr.conv", "room:ra"))
    +cs : List<&2, M.Change> = [M.RoomPosted{"p2", "ra", "Alpha", "new body", 0n, 5n}, M.RoomSet{"rb", "Changed membership", "ba", 6n}, M.MailMarked{"ba", "act-c", "done", 1n, 0n, 7n}, M.MailMarked{"bb", "act-c", "done", 1n, 0n, 8n}]
    +st2 : M.State = M.State.replay(cs, st)
    +cache2 : TM.Cache = TM.Cache.committed(cs, st2, cache)
    +next : TA.Actor = refresh(drafted, st2, cache2)
    equal("incremental refresh matches true canonical fold", TA.Actor.ui(next), U.Ui.fold(cs, folded))
    C.Check.str("authoritative refresh retains private draft", U.Ui.scratch(TA.Actor.ui(next), "@f.mrreply"), "private draft 🙂")
    C.Check.str("new body invalidates only open read marker", U.Ui.scratch(TA.Actor.ui(next), "@mr.read.dirty"), "1")
    C.Check.str("new canonical mail invalidates list token", Bool.show(String.eq(U.Ui.scratch(TA.Actor.ui(next), "@mr.loaded"), U.Mailv.token(TA.Actor.ui(next)))), "False")
    +nextReady : TA.Actor = TA.Actor.mail_ready(next)
    C.Check.str("refresh queues new readonly list", F.methods(TA.Actor.queued(nextReady)), "mail.list|")
    +nextDone : TA.Actor = list_reply(nextReady)
    C.Check.str("refresh cannot resurrect an empty aggregate page", listed(nextDone), "room:ra,act-c,room:rb,")
    +marked : List<&2, M.Change> = [M.MailMarked{"ba", "room:ra", "done", 2n, 0n, 9n}]
    +st3 : M.State = M.State.replay(marked, st2)
    +cleanRead : TA.Actor = F.with_ui(next, U.Ui.scratch_set(TA.Actor.ui(next), "@mr.read.dirty", ""))
    +markRefresh : TA.Actor = refresh(cleanRead, st3, TM.Cache.committed(marked, st3, cache2))
    C.Check.str("mark-only refresh never triggers read loop", U.Ui.scratch(TA.Actor.ui(markRefresh), "@mr.read.dirty"), "")
    +same : TA.Actor = refresh(markRefresh, st3, TM.Cache.committed(Nil{}, st3, TM.Cache.committed(marked, st3, cache2)))
    C.Check.str("unchanged refresh retains exact request generation", Nat.show(U.Ui.rid(TA.Actor.ui(same))), Nat.show(U.Ui.rid(TA.Actor.ui(markRefresh))))
    C.Check.str("nonmail activity retains cached mailbox revision", Nat.show(TM.Cache.revision(TM.Cache.committed([M.SettingSet{"unrelated", "on", 10n}], M.State.apply(st3, M.SettingSet{"unrelated", "on", 10n}), cache2))), Nat.show(TM.Cache.revision(cache2)))
