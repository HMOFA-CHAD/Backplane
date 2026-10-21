import Base
import ../src/core/client.bend as U
import ../src/core/mailview.bend as MVW

# A Room recipient is explicit and cannot alter ordinary target lists.
law mail_room_target_nonroom_unchanged:
  for +os: List<&2, MVW.Opt>
  {U.Mailv.room.target.ref(None{}, os) == os : List<&2, MVW.Opt>}

law mail_room_target_single_empty_option:
  for +room: String
  {U.Mailv.room.target.rows(Nil{}, room, False{}) == [MVW.Opt{room, "Room"}] : List<&2, MVW.Opt>}

law mail_room_target_duplicate_dropped:
  for +addr: String
  for +label: String
  for +rest: List<&2, MVW.Opt>
  {U.Mailv.room.target.row(True{}, True{}, addr, label, rest) == rest : List<&2, MVW.Opt>}

def mail_room_target_nonroom_unchanged(os): {==}
def mail_room_target_single_empty_option(room): {==}
def mail_room_target_duplicate_dropped(addr, label, rest): {==}
