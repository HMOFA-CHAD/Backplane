import Base
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
