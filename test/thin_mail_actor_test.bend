import Base
import ./check.bend as C
import ./thin_mail_actor_fixture.bend as F
import ../src/server/thin-actor.bend as TA
import ../src/server/thin-view.bend as V
import ../src/core/client.bend as U
import ../src/core/model.bend as M
import ../src/core/json.bend as J
import ../src/web/mail-actions.bend as MA

# Source-only handoff: the backend owner runs this in its coherent gate.
# Expected behavior assertions may expose missing actor view fencing. They
# must not be changed to bless the currently observed implementation.
def bool(+name: String, got: Bool, want: Bool) -> IO(Unit):
  C.Check.str(name, Bool.show(got), Bool.show(want))

def draft(+a: TA.Actor) -> String:
  U.Ui.scratch(TA.Actor.ui(a), "@f.mrreply")

def send_ack(+a: TA.Actor) -> TA.Actor:
  TA.Actor.reply(a, True{}, "public-hub", F.reply(MA.MA.get(TA.Actor.ui(a), "rid"), True{}, F.obj("{}")))

def read_reply(+a: TA.Actor, text: String) -> TA.Actor:
  TA.Actor.reply(a, True{}, "public-hub", F.reply(U.Ui.scratch(TA.Actor.ui(a), "@mr.read"), True{}, F.body(text)))

def captured() -> IO(Unit):
  do IO<Unit>:
    +typed : TA.Actor = F.field(F.base(), "captured é🙂\nsecond line")
    +fresh : TA.Actor = F.refresh(typed, F.request("ba", 1n), "view-a")
    C.Check.str("field survives fresh thin request before Send", draft(fresh), "captured é🙂\nsecond line")
    +rpc : J.Json = F.find(F.commands(F.action(fresh, "mail-send", "")), "mail.send")
    C.Check.str("Send uses normal mail.send RPC", J.Json.get_str(rpc, "m", ""), "mail.send")
    C.Check.str("Send exact captured Unicode body", J.Json.get_str(J.Json.get_obj(rpc, "p"), "text", ""), "captured é🙂\nsecond line")
    C.Check.str("Send exact captured conversation", J.Json.get_str(J.Json.get_obj(rpc, "p"), "conv", ""), "room:ra")
    C.Check.str("Send exact captured recipient", J.Json.get_str(J.Json.get_obj(rpc, "p"), "to", ""), "room:ra")
    +sent : TA.Actor = F.step(fresh, "mail-send", "")
    C.Check.str("normal MA captured send state", MA.MA.get(TA.Actor.ui(sent), "state"), "sending")
    C.Check.str("send capture retains draft until commit", draft(sent), "captured é🙂\nsecond line")
    C.Check.str("pending captured send cannot emit a duplicate mutation", J.Json.get_str(F.find(F.commands(F.action(sent, "mail-send", "")), "mail.send"), "m", "absent"), "absent")
    C.Check.str("ordinary correlated ACK reaches MA", MA.MA.get(TA.Actor.ui(send_ack(sent)), "state"), "ack")
    C.Check.str("ACK alone does not clear draft", draft(send_ack(sent)), "captured é🙂\nsecond line")
    +reading : TA.Actor = F.read(F.base())
    +received : TA.Actor = read_reply(reading, "complete received é🙂\nsecond line")
    C.Check.str("ordinary correlated read reaches typed Mailv body", F.bubbles(U.Mailv.bubbles(TA.Actor.ui(received))), "complete received é🙂\nsecond line")
    C.Check.str("completed read consumes its original correlation", U.Ui.scratch(TA.Actor.ui(received), "@mr.req:" ++ U.Ui.scratch(TA.Actor.ui(reading), "@mr.read")), "")
    bool("recognized read marks actor dirty", TA.Actor.dirty(received), True{})
    bool("ordinary read result queues only nonmutating followups", F.only_reads(TA.Actor.queued(received)), True{})

def filed(+a: TA.Actor) -> TA.Actor:
  read_reply(F.read(F.with_ui(send_ack(a), U.Ui.fold([M.MailPosted{"public-filed", "room:ra", "person", "room:ra", "room", "ra", "fyi", "captured", 27n, 102n}], TA.Actor.ui(send_ack(a))))), "captured é🙂\nsecond line")

def newer_drafts() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("header plus full read settles normal MA reconciliation", MA.MA.get(TA.Actor.ui(filed(F.sent())), "state"), "filed")
    C.Check.str("exact filed draft clears only after header and body", draft(filed(F.sent())), "")
    +newer : TA.Actor = F.field(F.sent(), "newer draft 漢字")
    C.Check.str("newer nonempty draft survives old ACK", draft(send_ack(newer)), "newer draft 漢字")
    C.Check.str("newer nonempty draft survives old committed body", draft(filed(newer)), "newer draft 漢字")
    +empty : TA.Actor = F.field(F.sent(), "")
    C.Check.str("newer empty draft survives refresh", draft(F.refresh(empty, F.request("ba", 1n), "view-a")), "")
    C.Check.str("newer empty draft survives old ACK", draft(send_ack(empty)), "")
    C.Check.str("newer empty draft survives old committed body", draft(filed(empty)), "")

def isolation() -> IO(Unit):
  do IO<Unit>:
    +a : TA.Actor = F.sent()
    +other : TA.Actor = F.actor("ba", "other-connection", "room:ra", 200n)
    +a_ack : J.Json = F.reply(MA.MA.get(TA.Actor.ui(a), "rid"), True{}, F.obj("{}"))
    +foreign : TA.Actor = TA.Actor.reply(other, True{}, "public-hub", a_ack)
    C.Check.str("fresh second connection cannot borrow correlation", MA.MA.get(TA.Actor.ui(foreign), "state"), "")
    bool("foreign correlation leaves second connection clean", TA.Actor.dirty(foreign), False{})
    +unrelated : TA.Actor = F.step(F.field(other, "other connection draft"), "mail-send", "")
    C.Check.str("connection fixture uses distinct live request IDs", Bool.show(String.eq(MA.MA.get(TA.Actor.ui(a), "rid"), MA.MA.get(TA.Actor.ui(unrelated), "rid"))), "False")
    C.Check.str("other connection pending send ignores A result", MA.MA.get(TA.Actor.ui(TA.Actor.reply(unrelated, True{}, "public-hub", a_ack)), "state"), "sending")
    C.Check.str("other connection retains its own captured draft", draft(TA.Actor.reply(unrelated, True{}, "public-hub", a_ack)), "other connection draft")
    +changed_target : TA.Actor = F.refresh(a, F.request("bb", 1n), "view-b")
    bool("new target refuses previous target ACK", TA.Actor.dirty(TA.Actor.reply(changed_target, True{}, "public-hub", a_ack)), False{})
    +changed_view : TA.Actor = F.refresh(a, F.request("ba", 1n), "replacement-view")
    bool("same target replacement view refuses old ACK", TA.Actor.dirty(TA.Actor.reply(changed_view, True{}, "public-hub", a_ack)), False{})
    # Actor.reply has no connection generation/view argument; equal numeric
    # IDs on two active sockets require server dispatch guard coverage too.

def duplicate_results() -> IO(Unit):
  do IO<Unit>:
    +a : TA.Actor = F.sent()
    +id : String = MA.MA.get(TA.Actor.ui(a), "rid")
    +settled : TA.Actor = TA.Actor.clean(send_ack(a))
    +duplicate : TA.Actor = TA.Actor.reply(settled, True{}, "public-hub", F.reply(id, False{}, F.obj("{}")))
    C.Check.str("duplicate contradictory ACK cannot change state", MA.MA.get(TA.Actor.ui(duplicate), "state"), "ack")
    bool("duplicate result does not dirty actor again", TA.Actor.dirty(duplicate), False{})
    +reading : TA.Actor = F.read(F.base())
    +read_id : String = U.Ui.scratch(TA.Actor.ui(reading), "@mr.read")
    +first : TA.Actor = TA.Actor.clean(read_reply(reading, "first exact body"))
    +late : TA.Actor = TA.Actor.reply(first, True{}, "public-hub", F.reply(read_id, True{}, F.body("contradictory duplicate body")))
    C.Check.str("read result applies at most once", F.bubbles(U.Mailv.bubbles(TA.Actor.ui(late))), "first exact body")
    C.Check.str("duplicate read cannot bump typed store revision", Nat.show(U.Mailv.rev(TA.Actor.ui(late))), Nat.show(U.Mailv.rev(TA.Actor.ui(first))))
    bool("duplicate read cannot dirty settled actor", TA.Actor.dirty(late), False{})
    bool("unknown request result stays ignored", TA.Actor.dirty(TA.Actor.reply(TA.Actor.clean(F.base()), True{}, "public-hub", F.reply("999999", True{}, F.body("unknown body")))), False{})

def attack(+a: TA.Actor) -> J.Json:
  V.Obj.put(F.request("ba", 1n), "session", J.Json.obj([
    J.KV{"rid", J.Num{"1"}}, J.KV{"drafts", F.obj("{\"a\":\"ordinary draft\",\"b\":\"foreign thread\",\"@f.mrreply\":\"injected\",\"@mr.read\":\"777\",\"@mr.req:777\":\"injected\"}")},
    J.KV{"outbox", F.obj("{\"injected\":\"mail.send\"}")},
    J.KV{"info", J.Json.obj([J.KV{"@f.mrreply", J.Str{"injected"}}, J.KV{"@mr.conv", J.Str{"room:rb"}}, J.KV{"@mr.read", J.Str{"777"}},
      J.KV{"@mr.req:777", J.Str{"injected"}}, J.KV{MA.MA.key(TA.Actor.ui(a)) ++ "text", J.Str{"injected capture"}},
      J.KV{MA.MA.key(TA.Actor.ui(a)) ++ "rid", J.Str{"777"}}, J.KV{"origin", J.Str{"foreign-epoch"}}, J.KV{"fold:public", J.Str{"1"}}])}]))

def scratch_injection() -> IO(Unit):
  do IO<Unit>:
    +a : TA.Actor = F.sent()
    +safe : J.Json = TA.Actor.safe_input(F.state(), attack(a))
    +session : J.Json = J.Json.get_obj(safe, "session")
    C.Check.str("ordinary current-thread draft still accepted", J.Json.get_str(J.Json.get_obj(session, "drafts"), "a", ""), "ordinary draft")
    C.Check.str("wire cannot inject another thread draft", J.Json.get_str(J.Json.get_obj(session, "drafts"), "b", "absent"), "absent")
    C.Check.str("wire draft cannot inject mail form", J.Json.get_str(J.Json.get_obj(session, "drafts"), "@f.mrreply", "absent"), "absent")
    C.Check.str("wire info cannot inject form fields", J.Json.get_str(J.Json.get_obj(session, "info"), "@f.mrreply", "absent"), "absent")
    C.Check.str("wire info cannot inject correlation", J.Json.get_str(J.Json.get_obj(session, "info"), "@mr.req:777", "absent"), "absent")
    C.Check.str("wire cannot inject outbox", J.Json.get_str(J.Json.get_obj(session, "outbox"), "injected", "absent"), "absent")
    C.Check.str("permitted fold preference survives sanitization", J.Json.get_str(J.Json.get_obj(session, "info"), "fold:public", ""), "1")
    +refreshed : TA.Actor = F.refresh(a, attack(a), "view-a")
    C.Check.str("refresh retains private captured form", draft(refreshed), "captured é🙂\nsecond line")
    C.Check.str("refresh retains private captured send body", MA.MA.get(TA.Actor.ui(refreshed), "text"), "captured é🙂\nsecond line")
    C.Check.str("refresh rejects forged request id", MA.MA.get(TA.Actor.ui(refreshed), "rid"), MA.MA.get(TA.Actor.ui(a), "rid"))
    C.Check.str("refresh keeps actor conversation", U.Ui.scratch(TA.Actor.ui(refreshed), "@mr.conv"), "room:ra")
    bool("forged correlation cannot settle actor", TA.Actor.dirty(TA.Actor.reply(refreshed, True{}, "public-hub", F.reply("777", True{}, F.body("injected body")))), False{})
    +fresh : TA.Actor = TA.Actor.refresh(Nil{}, True{}, F.state(), F.info(), F.obj("{}"), 100n, attack(a), "fresh-view")
    C.Check.str("cached scratch cannot seed fresh actor draft", draft(fresh), "")
    bool("cached scratch cannot seed fresh actor correlation", TA.Actor.dirty(TA.Actor.reply(fresh, True{}, "public-hub", F.reply("777", True{}, F.body("injected body")))), False{})

def queued_reads() -> IO(Unit):
  do IO<Unit>:
    +commands : List<&2, J.Json> = [F.command("mail.send", "1"), F.command("mail.read", "2"), F.command("mail.mark", "3"),
      F.command("mail.list", "4"), F.command("mail.tag", "5"), F.command("mail.find", "6"), F.command("bots.post", "7"),
      V.Obj.put(F.command("mail.read", "8"), "type", J.Str{"copy"}), F.obj("{\"type\":\"send\",\"text\":\"broken-json\"}")]
    +base : TA.Actor = F.field(F.base(), "untouched draft")
    +queued : TA.Actor = TA.Actor.accept(base, V.ActResult{TA.Actor.ui(base), commands}, True{})
    C.Check.str("queued followups contain only exact read allowlist", F.methods(TA.Actor.queued(queued)), "mail.read|mail.list|mail.find|")
    C.Check.str("queue capture cannot mutate draft", draft(queued), "untouched draft")
    C.Check.str("queue capture cannot start a send", MA.MA.get(TA.Actor.ui(queued), "state"), "")
    C.Check.str("draining clears queued commands", Nat.show(List.length(&2, J.Json, TA.Actor.queued(TA.Actor.clean(queued)))), "0")
    bool("draining clears dirty bit", TA.Actor.dirty(TA.Actor.clean(TA.Actor.mark_dirty(queued))), False{})

def main() -> IO(Unit):
  do IO<Unit>:
    captured()
    newer_drafts()
    isolation()
    duplicate_results()
    scratch_injection()
    queued_reads()
