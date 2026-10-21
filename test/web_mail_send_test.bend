import Base
import ./check.bend as C
import ../src/web/mail-actions.bend as W
import ../src/core/client.bend as U
import ../src/core/mail.bend as ML
import ../src/core/mailview.bend as MV
import ../src/core/model.bend as M
import ../src/core/json.bend as J

def yes(b: Bool) -> String:
  Bool.pick(String, b, "yes", "no")

def mail(id: String, at: Nat) -> ML.Mail:
  ML.Mail{id, "opaque|conversation", "person", "bot:bub", "message", "", "act", "identical text", 14n, at}

def state(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}: u

def fixture() -> U.Ui:
  W.MA.put(W.MA.put(W.MA.put(W.MA.put(U.Ui.scratch_set(U.Ui.init(1n), "@mr.conv", "opaque|conversation"), "to", "bot:bub"), "text", "identical text"), "previous", "previous-newest"), "state", "sending")

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("older identical cached header is not fresh", yes(W.MA.header([mail("previous-newest", 3n), mail("old-identical", 2n)], fixture(), "old-identical")), "no")
    C.Check.str("new committed header before boundary is fresh", yes(W.MA.header([mail("fresh", 4n), mail("previous-newest", 3n), mail("old-identical", 2n)], fixture(), "fresh")), "yes")
    C.Check.str("captured newest itself is not fresh", yes(W.MA.body([MV.Msg{"previous-newest", "person", "bot:bub", "message", "act", 3n, "identical text"}], fixture())), "no")
    C.Check.str("body without committed header does not file", yes(W.MA.body([MV.Msg{"fresh", "person", "bot:bub", "message", "act", 4n, "identical text"}], fixture())), "no")
    C.Check.str("disconnect blocks replay", W.MA.get(W.MA.online(fixture(), False{}), "state"), "unknown")
    C.Check.str("ACK is not filing", W.MA.get(W.MA.reply(True{}, fixture(), J.Json.obj([J.KV{"ok", J.Flag{True{}}}])), "state"), "ack")
    C.Check.str("confirmed filing preserves newer draft", U.Ui.scratch(W.MA.filed(True{}, U.Ui.scratch_set(fixture(), "@f.mrreply", "newer edit")), "@f.mrreply"), "newer edit")
    C.Check.str("confirmed filing clears only captured draft", U.Ui.scratch(W.MA.filed(True{}, U.Ui.scratch_set(fixture(), "@f.mrreply", "identical text")), "@f.mrreply"), "")
    C.Check.str("offline send preserves draft", U.Ui.scratch(state(W.MA.send(U.Ui.scratch_set(fixture(), "@f.mrreply", "draft"))), "@f.mrreply"), "draft")
