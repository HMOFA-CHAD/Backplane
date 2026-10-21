import Base
import ./check.bend as C
import ./web_mail_room_nodes.bend as W
import ../src/web/mail-actions.bend as MA
import ../src/web/mailroom.bend as WM
import ../src/core/client.bend as U
import ../src/core/model.bend as M
import ../src/core/mailview.bend as MV
import ../src/web/dom.bend as D

def status(recipient: String, automation: String, state: String) -> String:
  MA.MA.status(MA.MA.put(MA.MA.put(U.Ui.fold([M.SettingSet{"mail.on", automation, 1n}], U.Ui.init(1n)), "to", recipient), "state", state))

def targets(choice: String) -> List<&2, D.Node>:
  WM.WM.targets([MV.Opt{"bot:member", "Member"}, MV.Opt{"room:opaque|fixture", "Room"}], U.Ui.scratch_set(U.Ui.init(1n), "@mr.to", choice))

# The checks of test/tools/web_mail_room_status.mjs, run here so scripts/test.sh
# runs them too. An option reads label|data-value|click action|class has "on".
def opt(+n: D.Node) -> String:
  W.Wn.head(n) ++ "|" ++ W.Wn.attr(n, "data-value") ++ "|" ++ W.Wn.on(n, "click") ++ "|" ++ Bool.show(String.contains(W.Wn.attr(n, "class"), "on"))

def opts.go(xs: List<&2, D.Node>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case h <> t: opts.go(t, opt(h) <> acc)

def opts(choice: String) -> String:
  String.join(opts.go(targets(choice), Nil{}), " ; ")

def ons.go(xs: List<&2, D.Node>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case h <> t: ons.go(t, Bool.show(String.contains(W.Wn.attr(h, "class"), "on")) <> acc)

def ons(choice: String) -> String:
  String.join(ons.go(targets(choice), Nil{}), ",")

def committed(+to: String) -> IO(Unit):
  do IO<Unit>:
    C.Check.str(to ++ " committed OFF reports paused", status(to, "off", "filed"), "Filed; automation paused")
    C.Check.str(to ++ " committed ON reports filed", status(to, "on", "filed"), "Filed")

def main() -> IO(Unit):
  do IO<Unit>:
    committed("room:opaque|fixture")
    committed("bot:bub")
    C.Check.str("thread:fixture does not imply automation route", status("thread:fixture", "off", "filed"), "Filed")
    C.Check.str("person does not imply automation route", status("person", "off", "filed"), "Filed")
    C.Check.str("room ack does not imply committed filing", status("room:opaque|fixture", "off", "ack"), "Acknowledged; waiting for committed message")
    C.Check.str("room sending does not imply committed filing", status("room:opaque|fixture", "off", "sending"), "Sending; draft preserved")
    C.Check.str("room unknown does not imply committed filing", status("room:opaque|fixture", "off", "unknown"), "Outcome unknown; check the conversation before sending again. Draft preserved.")
    C.Check.str("canonical Room option renders exact opaque target without auto selection", opts(""), "Member|bot:member|mail-to|False ; Room|room:opaque|fixture|mail-to|False")
    C.Check.str("existing member choice is preserved when Room option is present", ons("bot:member"), "True,False")
    C.Check.str("explicit Room selection renders only that option selected", ons("room:opaque|fixture"), "False,True")
