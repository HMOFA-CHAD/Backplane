import Base
import ../src/core/hub.bend as H
import ../src/core/bothub.bend as BHS
import ../src/core/model.bend as M
import ../src/core/json.bend as J
import ../src/core/bot.bend as BOT
import ../src/core/client.bend as U

# Quiet human room mail preserves canonical history without waking members.
law mail_room_invalid_request_is_error:
  for +s: M.State
  for +now: Nat
  for +client: U32
  for +id: String
  for +p: J.Json
  {H.Mail.ui.request.valid(False{}, s, now, client, id, p) == H.Step.outs([H.Reply.err(client, id, "invalid mail target")]) : H.Step}

law mail_room_invalid_room_is_error:
  for +s: M.State
  for +now: Nat
  for +client: U32
  for +id: String
  for +p: J.Json
  for +r: BOT.Room
  {BHS.Bots.mail.room.quiet.valid(False{}, s, now, client, id, p, r) == H.Step.outs([H.Reply.err(client, id, "invalid mail room")]) : H.Step}

law mail_room_send_no_eager_events:
  for +s: M.State
  for +now: Nat
  for +client: U32
  for +id: String
  for +p: J.Json
  for +room: String
  for +subject: String
  for +members: List<&2, String>
  for +made: Nat
  {H.Queue.changes(BHS.Bots.mail.room.quiet.valid(True{}, s, now, client, id, p, BOT.Room{room, subject, members, made, False{}})) == Nil{} : List<&2, M.Change>}

law mail_room_set_updates_client_index:
  for +u: U.Ui
  for +room: String
  for +name: String
  for +members: String
  for +at: Nat
  {U.Mailv.index.update(M.RoomSet{room, name, members, at}, u) == U.Mailv.index.room(u, "room:" ++ room) : U.Ui}

law mail_room_post_updates_client_index:
  for +u: U.Ui
  for +id: String
  for +room: String
  for +from: String
  for +text: String
  for +hop: Nat
  for +at: Nat
  {U.Mailv.index.update(M.RoomPosted{id, room, from, text, hop, at}, u) == U.Mailv.index.conv(u, "room:" ++ room) : U.Ui}

law mail_room_post_affects_room_only:
  for +id: String
  for +room: String
  for +from: String
  for +text: String
  for +hop: Nat
  for +at: Nat
  {U.Mailv.change_conv(M.RoomPosted{id, room, from, text, hop, at}) == "room:" ++ room : String}

def mail_room_invalid_request_is_error(s, now, client, id, p): {==}
def mail_room_invalid_room_is_error(s, now, client, id, p, r): {==}
def mail_room_send_no_eager_events(s, now, client, id, p, room, subject, members, made): {==}
def mail_room_set_updates_client_index(u, room, name, members, at): {==}
def mail_room_post_updates_client_index(u, id, room, from, text, hop, at): {==}
def mail_room_post_affects_room_only(id, room, from, text, hop, at): {==}
