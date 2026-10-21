import Base
import ../src/core/hub.bend as H
import ../src/core/model.bend as M
import ../src/core/json.bend as J
import ../src/core/bot.bend as BOT

law mail_ui_dispatch_available:
  for +i: Nat
  for +s: M.State
  for +now: Nat
  for +client: U32
  for +id: String
  for +p: J.Json
  {H.Mail.request.ui(i, s, now, client, id, p) == H.Mail.request.on(True{}, i, s, now, client, id, p) : H.Step}

law mail_ui_body_read_available:
  for +s: M.State
  for +now: Nat
  for +client: U32
  for +id: String
  for +p: J.Json
  {H.Mail.request.ui(1n, s, now, client, id, p) == H.Mail.read(s, now, client, id, p) : H.Step}

law mail_ui_invalid_target_no_effect:
  for +s: M.State
  for +now: Nat
  for +thread: String
  for +p: J.Json
  for +msg: String
  {H.Mail.ui.send.valid(False{}, s, now, thread, p, msg) == H.Step.none() : H.Step}

law mail_ui_owned_target_uses_mailbox:
  for +s: M.State
  for +now: Nat
  for +thread: String
  for +p: J.Json
  for +msg: String
  {H.Mail.ui.send.valid(True{}, s, now, thread, p, msg) == H.Mail.send.bot(BOT.World.is_bot_thread(M.State.bots(s), thread), True{}, s, now, "person", thread, p, msg) : H.Step}

def mail_ui_dispatch_available(i, s, now, client, id, p): {==}
def mail_ui_body_read_available(s, now, client, id, p): {==}
def mail_ui_invalid_target_no_effect(s, now, thread, p, msg): {==}
def mail_ui_owned_target_uses_mailbox(s, now, thread, p, msg): {==}
