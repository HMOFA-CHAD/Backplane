import Base
import ./check.bend as C
import ../src/core/json.bend as J
import ../src/core/codec.bend as K
import ../src/core/model.bend as M
import ../src/core/notice.bend as NO
import ../src/core/hub.bend as H
import ../src/core/bothub.bend as BH
import ../src/core/client.bend as U
import ../src/mobile/notify.bend as N

# The alert policy (core/notice.bend's Policy.*): the person is alerted
# when needed, when work settles, or for what they scheduled. Every case is
# a replay; the record is what the hub writes and every client follows.

def s(cs: List<&2, M.Change>) -> M.State:
  NO.Policy.demo.s(cs)

def cat(xss: List<&2, List<&2, M.Change>>) -> List<&2, M.Change>:
  NO.Policy.demo.cat(xss)

def said(cs: List<&2, M.Change>) -> String:
  NO.Policy.said(cs)

def rec(+cs: List<&2, M.Change>) -> NO.AlertRec:
  NO.Alert.parse(NO.Policy.demo.val(cs))

def len(xs: List<&2, J.Json>) -> String:
  Nat.show(List.length(&2, J.Json, xs))

# the phone's alerts for thread t1 holding cur after a frame, having held prev
def phone(+prev: String, +cur: String, +desk: String) -> String:
  len(N.Note.ralerts(U.Ui.threads(N.Note.demo.s(cur)), [N.RSeen{"t1", prev}], N.Note.demo.s(cur), desk))

def main() -> IO(Unit):
  do IO<Unit>:
    # the record
    +line : String = NO.Alert.line("note", "note-n1", "m1", "12.34", "Order sweatpants")
    C.Check.str("record kind", NO.Alert.kind(NO.Alert.parse(line)), "note")
    C.Check.str("record key", NO.Alert.rkey(NO.Alert.parse(line)), "note-n1")
    C.Check.str("record settled", NO.Alert.rsettled(NO.Alert.parse(line)), "m1")
    C.Check.str("record stamp", NO.Alert.rstamp(NO.Alert.parse(line)), "12.34")
    C.Check.str("record text", NO.Alert.rtext(NO.Alert.parse(line)), "Order sweatpants")
    C.Check.str("record stamp time", Nat.show(NO.Alert.at(NO.Alert.parse(line))), "12")
    C.Check.str("an absent record is empty", NO.Alert.kind(NO.Alert.get(M.State.empty(), "t1")) ++ NO.Alert.memory(M.State.empty(), "t1"), "")
    C.Check.str("a text keeps its tabs out", NO.Alert.text("a\tb\nc", 20n), "a b c")
    # the person's message
    C.Check.str("direct text", Bool.show(NO.Policy.direct("m1", "do it")), "True")
    C.Check.str("a link id is not", Bool.show(NO.Policy.direct("t:x:1", "do it")), "False")
    C.Check.str("a routine is not", Bool.show(NO.Policy.direct("m1", "[routine: daily]\ngo")), "False")
    C.Check.str("a room delivery is not", Bool.show(NO.Policy.direct("m1", "[message from you in #r]\nhi")), "False")
    C.Check.str("a Backplane note is not", Bool.show(NO.Policy.direct("m1", "[Backplane] Launched thread x")), "False")
    C.Check.str("the person from another machine is", Bool.show(NO.Policy.direct("m1", "[message from person@desk]\nhi")), "True")
    C.Check.str("the newest person message", NO.Per.id(NO.Policy.person(s(cat([NO.Policy.demo.ask(), NO.Policy.demo.run("t1", "m2", "again", 20n), NO.Policy.demo.run("t1", "t:t0:1", "x", 21n)])), "t1")), "m2")
    # settling
    C.Check.str("quiet cases", Nat.show(NO.Policy.demo.quiet()), "0")
    C.Check.str("settle once", NO.Policy.demo.once(), "done -")
    C.Check.str("settle after the launched thread", NO.Policy.demo.launch(), "- done")
    C.Check.str("fail only for the person", NO.Policy.demo.fail.p(), "fail -")
    C.Check.str("setting off", NO.Policy.demo.off(), "_ m1 -")
    C.Check.str("notify.all", NO.Policy.demo.all(), "done room-r1")
    +done : List<&2, M.Change> = NO.Policy.end(s(NO.Policy.demo.ask()), 13n, "t1", "completed")
    C.Check.str("done key", NO.Alert.rkey(rec(done)), "turn-t1")
    C.Check.str("done keeps the person's id", NO.Alert.rsettled(rec(done)), "m1")
    C.Check.str("done is stamped", NO.Alert.rstamp(rec(done)), "13." ++ Nat.show(H.Hub.seq(s(NO.Policy.demo.ask()))))
    C.Check.str("a plain thread's second turn with no new message", said(NO.Policy.end(s(cat([NO.Policy.demo.ask(), done, NO.Policy.demo.run("t1", "r2", "[Backplane] x", 30n), NO.Policy.demo.done("t1", 31n)])), 32n, "t1", "completed")), "-")
    C.Check.str("a new person message settles again", said(NO.Policy.end(s(cat([NO.Policy.demo.ask(), done, NO.Policy.demo.run("t1", "m2", "more", 30n), NO.Policy.demo.done("t1", 31n)])), 32n, "t1", "completed")), "done")
    C.Check.str("a queued message is not settled", said(NO.Policy.end(s(cat([NO.Policy.demo.ask(), [M.TurnQueued{"t1", "m9", "next", 12n}]])), 13n, "t1", "completed")), "-")
    C.Check.str("an open ask is not settled", said(NO.Policy.end(s(cat([NO.Policy.demo.ask(), [M.AskOpened{"k1", "t1", "approval", "Bash", "ls", "", 12n}]])), 13n, "t1", "completed")), "-")
    C.Check.str("a stop ends the episode quietly", said(NO.Policy.end(s(cat([NO.Policy.demo.base(), NO.Policy.demo.run("t1", "m1", "x", 10n), [M.TurnChanged{"t1", M.Interrupted{}, 12n}]])), 13n, "t1", "stopped")), "_")
    C.Check.str("a failed turn with work out still alerts", said(NO.Policy.end(s(cat([NO.Policy.demo.base(), NO.Policy.demo.run("t1", "m1", "x", 10n), [M.WorkSet{"t1", "bg", "a\tx", 11n}], NO.Policy.demo.fail("t1", 12n)])), 13n, "t1", "failed")), "fail")
    C.Check.str("settled off: failure is quiet too", said(NO.Policy.end(s(cat([[M.SettingSet{"notify.settled", "off", 1n}], NO.Policy.demo.base(), NO.Policy.demo.run("t1", "m1", "x", 10n), NO.Policy.demo.fail("t1", 12n)])), 13n, "t1", "failed")), "_")
    # settings
    C.Check.str("needs defaults on", Bool.show(NO.Policy.on(M.State.empty(), "needs")), "True")
    C.Check.str("all defaults off", Bool.show(NO.Policy.on(M.State.empty(), "all")), "False")
    C.Check.str("an unknown name is off", Bool.show(NO.Policy.on(M.State.empty(), "nope")), "False")
    C.Check.str("a setting turns one off", Bool.show(NO.Policy.on(s([M.SettingSet{"notify.reminders", "off", 1n}]), "reminders")), "False")
    C.Check.str("a setting turns all on", Bool.show(NO.Policy.on(s([M.SettingSet{"notify.all", "on", 1n}]), "all")), "True")
    # asks, merges, the hub's passes
    +ask : List<&2, M.Change> = NO.Policy.ask(s(NO.Policy.demo.ask()), 20n, "t1", "Bash", "ls -l\nmore")
    C.Check.str("ask kind", said(ask), "ask")
    C.Check.str("ask key", NO.Alert.rkey(rec(ask)), "ask-t1")
    C.Check.str("ask text is one line", NO.Alert.rtext(rec(ask)), "Bash ls -l more")
    C.Check.str("ask off", NO.Policy.demo.ask.k(s(NO.Policy.demo.ask())), "ask _")
    C.Check.str("ask alerted", Nat.show(H.Alerts.demo.asks(False{})), "1")
    C.Check.str("ask off: none", Nat.show(H.Alerts.demo.asks(True{})), "0")
    C.Check.str("a step with an ask gets its record", said(H.Alerts.changes(s(NO.Policy.demo.ask()), [M.AskOpened{"k1", "t1", "input", "", "Which?", "", 20n}])), "ask")
    C.Check.str("a step with no ask is left alone", Nat.show(List.length(&2, M.Change, H.Alerts.changes(s(NO.Policy.demo.ask()), [M.TurnChanged{"t1", M.Running{}, 20n}]))), "1")
    C.Check.str("merge", H.Alerts.demo.merge(), "merged 1")
    C.Check.str("merge body", NO.Alert.body(rec(NO.Policy.merged(s(NO.Policy.demo.ask()), 30n, "t1", "http://x/1"))), "Merged: http://x/1")
    C.Check.str("merge without a url", NO.Alert.body(rec(NO.Policy.merged(s(NO.Policy.demo.ask()), 30n, "t1", ""))), "Merged: its branch")
    C.Check.str("a turn end tells the server once", H.Alerts.demo.end(), "done 1")
    C.Check.str("a setting that is no record tells no one", Nat.show(List.length(&2, H.Out, H.Alerts.outs([M.SettingSet{"notify.all", "on", 1n}], Nil{}))), "0")
    C.Check.str("a record with no kind tells no one", Nat.show(List.length(&2, H.Out, H.Alerts.outs([M.SettingSet{"alert.t1", NO.Alert.line("", "", "m1", "1.1", ""), 1n}], Nil{}))), "0")
    # a reminder come due (remind_person)
    +rem : List<&2, M.Change> = NO.Policy.reminder(s(NO.Policy.demo.ask()), 40n, "t1", "r7", "Call the bank")
    C.Check.str("reminder kind", said(rem), "reminder")
    C.Check.str("reminder key", NO.Alert.rkey(rec(rem)), "remind-r7")
    C.Check.str("reminder text", NO.Alert.rtext(rec(rem)), "Call the bank")
    C.Check.str("reminder keeps the memory", NO.Alert.rsettled(rec(rem)), "")
    C.Check.str("reminder alerts both ways", NO.Policy.demo.reminder(), "reminder _")
    C.Check.str("reminder tells the server", Nat.show(List.length(&2, H.Out, H.Alerts.outs(rem, Nil{}))), "1")
    C.Check.str("a desk never holds a reminder", Bool.show(NO.Alert.holds("reminder")), "False")
    C.Check.str("phone: a reminder is never held", phone("", N.Note.demo.rec("reminder"), "t1"), "1")
    # notify_person
    C.Check.str("notify refuses chatter", BH.Notify.demo.chatter(), "refused refused refused")
    C.Check.str("notify reminder in a routine only", BH.Notify.demo.routine(), "note note refused")
    C.Check.str("notify needs_you once", BH.Notify.demo.once(), "note refused")
    C.Check.str("notify done settles", BH.Notify.demo.done(), "note refused -")
    C.Check.str("notify with the setting off", BH.Notify.demo.off(), "_")
    C.Check.str("notify is a bot tool", Bool.show(BH.Bots.tool.is("notify_person")), "True")
    C.Check.str("bot tool numbers kept", Nat.show(K.Codec.pos(BH.Bots.names(), "plane_read")), "20")
    # the phones follow the record
    +d : String = N.Note.demo.rec("done")
    C.Check.str("phone: a changed record alerts", phone("", d, ""), "1")
    C.Check.str("phone: the same value does not", phone(d, d, ""), "0")
    C.Check.str("phone: a record with no kind does not", phone("", N.Note.demo.rec(""), ""), "0")
    C.Check.str("phone: held under a watching desk", phone("", d, "t1"), "0")
    C.Check.str("phone: a note is never held", phone("", N.Note.demo.rec("note"), "t1"), "1")
    C.Check.str("phone: an ask is held", phone("", N.Note.demo.rec("ask"), "t1"), "0")
    C.Check.str("phone: another thread's desk holds nothing", phone("", d, "t9"), "1")
    C.Check.str("phone: body of a done is the reply", J.Json.get_str(Maybe.default(&2, J.Json, List.head(&2, J.Json, N.Note.ralerts(U.Ui.threads(N.Note.demo.s(d)), [N.RSeen{"t1", ""}], N.Note.demo.s(d), "")), J.Null{}), "body", ""), "Finished")
    C.Check.str("phone: body of a merge", J.Json.get_str(Maybe.default(&2, J.Json, List.head(&2, J.Json, N.Note.ralerts(U.Ui.threads(N.Note.demo.s(NO.Alert.line("merged", "turn-t1", "m1", "1.1", "http://x/1"))), [N.RSeen{"t1", ""}], N.Note.demo.s(NO.Alert.line("merged", "turn-t1", "m1", "1.1", "http://x/1")), "")), J.Null{}), "body", ""), "Merged: http://x/1")
    C.Check.str("phone: body of a note", J.Json.get_str(Maybe.default(&2, J.Json, List.head(&2, J.Json, N.Note.ralerts(U.Ui.threads(N.Note.demo.s(NO.Alert.line("note", "note-1", "m1", "1.1", "Buy milk"))), [N.RSeen{"t1", ""}], N.Note.demo.s(NO.Alert.line("note", "note-1", "m1", "1.1", "Buy milk")), "")), J.Null{}), "body", ""), "Buy milk")
    C.Check.str("phone: the record's key is the alert's", J.Json.get_str(Maybe.default(&2, J.Json, List.head(&2, J.Json, N.Note.ralerts(U.Ui.threads(N.Note.demo.s(d)), [N.RSeen{"t1", ""}], N.Note.demo.s(d), "")), J.Null{}), "key", ""), "turn-t1")
    C.Check.str("desk holds", Bool.show(NO.Alert.holds("done")) ++ Bool.show(NO.Alert.holds("note")), "TrueFalse")
