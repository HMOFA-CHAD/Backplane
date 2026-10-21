import Base
import ../core/client.bend as U
import ../core/json.bend as J
import ../core/model.bend as M
import ../core/mail.bend as ML
import ../core/mailview.bend as MV

# Human sends are one-shot. An ACK is not a committed body and a reconnect
# must not manufacture another mail ID. Keep the captured draft until both
# the journal header and complete body have arrived from the owning hub.
def MA.key(+u: U.Ui) -> String:
  +owner = U.Mailv.owner(u)
  +origin = U.Ui.info(u, "origin")
  "@wm:" ++ Nat.show(String.length(origin)) ++ ":" ++ origin ++ Nat.show(String.length(owner)) ++ ":" ++ owner ++ U.Ui.scratch(u, "@mr.conv") ++ ":"

def MA.get(+u: U.Ui, +field: String) -> String:
  U.Ui.scratch(u, MA.key(u) ++ field)

def MA.put(+u: U.Ui, +field: String, value: String) -> U.Ui:
  U.Ui.scratch_set(u, MA.key(u) ++ field, value)

def MA.busy(+u: U.Ui) -> Bool:
  Bool.or(String.eq(MA.get(u, "state"), "sending"), Bool.or(String.eq(MA.get(u, "state"), "ack"), String.eq(MA.get(u, "state"), "unknown")))

def MA.send.ready(ok: Bool, +u: U.Ui) -> U.Act:
  match ok:
    case False{}: U.Act{u, Nil{}}
    case True{}:
      +text = U.Ui.scratch(u, "@f.mrreply")
      +to = U.Ui.scratch(u, "@mr.to")
      +conv = U.Ui.scratch(u, "@mr.conv")
      +last = ML.Mail.id(ML.Box.newest(M.State.mail(U.Ui.state(u)), conv))
      U.Ui.rpc(MA.put(MA.put(MA.put(MA.put(MA.put(MA.put(u, "state", "sending"), "rid", Nat.show(U.Ui.rid(u))), "text", text), "to", to), "previous", last), "error", ""), "mail.send", [J.KV{"conv", J.Str{conv}}, J.KV{"to", J.Str{to}}, J.KV{"text", J.Str{text}}, J.KV{"want", J.Str{"act"}}])

def MA.connected(u: U.Ui) -> Bool:
  match u:
    case U.Ui{_, _, _, _, _, online, _, _, _, _, _, _, _, _, _, _, _}: online

def MA.send(+u: U.Ui) -> U.Act:
  MA.send.ready(Bool.and(MA.connected(u), Bool.and(Bool.not(MA.busy(u)), Bool.and(Bool.not(String.is_empty(U.Ui.scratch(u, "@mr.to"))), Bool.not(String.is_empty(String.trim(U.Ui.scratch(u, "@f.mrreply"))))))), u)

def MA.receiver(+u: U.Ui) -> String:
  Bool.pick(String, String.eq(U.Mailv.bot(u), "*"), "", U.Mailv.bot(u))

def MA.first_bot(ps: List<&2, String>) -> String:
  match ps:
    case Nil{}: ""
    case +p <> rest:
      Bool.pick(String, String.starts_with(p, "bot:"), String.drop(p, 4n), MA.first_bot(rest))

def MA.participant(+ps: List<&2, String>, +preferred: String) -> String:
  Bool.pick(String, ML.Parts.has(ps, "bot:" ++ preferred, False{}), preferred, MA.first_bot(ps))

def MA.open.restore(a: U.Act) -> U.Act:
  match a:
    case U.Act{+u, cs}: U.Act{U.Ui.scratch_set(u, "@f.mrreply", MA.get(u, "draft")), cs}

def MA.open(+u: U.Ui, +conv: String) -> U.Act:
  +parts = ML.Conv.parts(ML.Box.conv(M.State.mail(U.Ui.state(u)), conv))
  +receiver = Bool.pick(String, String.eq(U.Mailv.bot(u), "*"), MA.participant(parts, U.Mailv.owner(u)), U.Mailv.bot(u))
  MA.open.restore(U.Ui.act(U.Ui.scratch_set(MA.put(u, "draft", U.Ui.scratch(u, "@f.mrreply")), "@mr.bot", receiver), "mail-open", conv))

def MA.mark.empty(empty: Bool, +u: U.Ui, status: String) -> U.Act:
  match empty:
    case True{}: U.Act{MA.put(u, "error", "Choose a receiver mailbox before marking this conversation."), Nil{}}
    case False{}: U.Mailv.request(u, "mail.mark", [J.KV{"bot", J.Str{MA.receiver(u)}}, J.KV{"conv", J.Str{U.Ui.scratch(u, "@mr.conv")}}, J.KV{"status", J.Str{status}}], "mark", MA.receiver(u))

def MA.mark(+u: U.Ui, status: String) -> U.Act:
  MA.mark.empty(String.is_empty(MA.receiver(u)), u, status)

def MA.action(i: Nat, +u: U.Ui, value: String) -> U.Act:
  match i:
    case 0n: MA.send(u)
    case 1n: MA.open(u, value)
    case 2n: MA.mark(u, value)
    case _: U.Act{u, Nil{}}

def MA.header(ms: List<&2, ML.Mail>, +u: U.Ui, +id: String) -> Bool:
  match ms:
    case Nil{}: False{}
    case +m <> rest:
      Bool.or(Bool.and(String.eq(ML.Mail.id(m), id), Bool.and(String.eq(ML.Mail.from(m), "person"), String.eq(ML.Mail.to(m), MA.get(u, "to")))), Bool.and(Bool.not(String.eq(ML.Mail.id(m), MA.get(u, "previous"))), MA.header(rest, u, id)))

def MA.body(ms: List<&2, MV.Msg>, +u: U.Ui) -> Bool:
  match ms:
    case Nil{}: False{}
    case MV.Msg{+id, +from, +to, _, _, _, +text} <> rest:
      Bool.or(Bool.and(Bool.not(String.eq(id, MA.get(u, "previous"))), Bool.and(String.eq(from, "person"), Bool.and(String.eq(to, MA.get(u, "to")), Bool.and(String.eq(text, MA.get(u, "text")), MA.header(ML.Box.mails_got(Map.get(List<&2, ML.Mail>, Nil{}, ML.Box.mails(M.State.mail(U.Ui.state(u))), U.Ui.scratch(u, "@mr.conv"))), u, id))))), MA.body(rest, u))

def MA.filed(yes: Bool, +u: U.Ui) -> U.Ui:
  match yes:
    case False{}: u
    case True{}:
      MA.put(U.Ui.scratch_set(u, "@f.mrreply", Bool.pick(String, String.eq(U.Ui.scratch(u, "@f.mrreply"), MA.get(u, "text")), "", U.Ui.scratch(u, "@f.mrreply"))), "state", "filed")

def MA.reconcile.busy(busy: Bool, +u: U.Ui) -> U.Ui:
  match busy:
    case False{}: u
    case True{}: MA.filed(MA.body(Map.values(&2, MV.Msg, MV.Read.msgs(MV.Mv.read_of(U.Mailv.cache(u), U.Ui.scratch(u, "@mr.conv")))), u), u)

def MA.reconcile(+u: U.Ui) -> U.Ui:
  MA.reconcile.busy(MA.busy(u), u)

def MA.reply(hit: Bool, +u: U.Ui, +o: J.Json) -> U.Ui:
  match hit:
    case False{}: u
    case True{}:
      MA.put(MA.put(u, "state", Bool.pick(String, J.Json.get_bool(o, "ok", False{}), "ack", "error")), "error", Bool.pick(String, J.Json.get_bool(o, "ok", False{}), "", J.Json.get_str(o, "error", "Mail request failed")))

def MA.error(has: Bool, +u: U.Ui, +o: J.Json) -> U.Ui:
  match has:
    case False{}: u
    case True{}: MA.put(u, "error", J.Json.get_str(o, "error", "Mail request failed"))

def MA.read_reply(current: Bool, +u: U.Ui, +o: J.Json) -> U.Ui:
  match current:
    case False{}: u
    case True{}: MA.put(u, "read-error", Bool.pick(String, J.Json.get_bool(o, "ok", True{}), "", J.Json.get_str(o, "error", "Message bodies could not be loaded")))

def MA.request_reply.kind(read: Bool, +u: U.Ui, +o: J.Json, +id: String, req: J.Json) -> U.Ui:
  match read:
    case True{}:
      MA.read_reply(Bool.and(String.eq(id, U.Ui.scratch(u, "@mr.read")), String.eq(J.Json.get_str(J.Json.get_obj(req, "p"), "conv", ""), U.Ui.scratch(u, "@mr.conv"))), u, o)
    case False{}: MA.error(Bool.not(J.Json.get_bool(o, "ok", True{})), u, o)

def MA.request_reply(known: Bool, +u: U.Ui, +o: J.Json, +id: String) -> U.Ui:
  match known:
    case False{}: u
    case True{}:
      +req = Maybe.default(&2, J.Json, J.Json.parse(U.Ui.scratch(u, "@mr.req:" ++ id)), J.Null{})
      MA.request_reply.kind(String.eq(J.Json.get_str(req, "m", ""), "mail.read"), u, o, id, req)

def MA.errors(+u: U.Ui) -> String:
  +read = MA.get(u, "read-error")
  +other = MA.get(u, "error")
  Bool.pick(String, String.is_empty(read), other, read ++ Bool.pick(String, String.is_empty(other), "", " · " ++ other))

def MA.recv(+u: U.Ui, +o: J.Json) -> U.Ui:
  +id = J.Json.as_raw(J.Json.get(o, "id"), "")
  +reply = String.eq(J.Json.get_str(o, "t", ""), "reply")
  MA.reply(Bool.and(reply, Bool.and(MA.busy(u), String.eq(id, MA.get(u, "rid")))), MA.request_reply(Bool.and(reply, Bool.not(String.is_empty(U.Ui.scratch(u, "@mr.req:" ++ id)))), u, o, id), o)

def MA.online(+u: U.Ui, +online: Bool) -> U.Ui:
  MA.put(u, "state", Bool.pick(String, Bool.and(Bool.not(online), MA.busy(u)), "unknown", MA.get(u, "state")))

def MA.status(+u: U.Ui) -> String:
  +state = MA.get(u, "state")
  Bool.pick(String, String.eq(state, "filed"), Bool.pick(String, Bool.and(Bool.or(String.starts_with(MA.get(u, "to"), "bot:"), String.starts_with(MA.get(u, "to"), "room:")), Bool.not(String.eq(M.Setting.get(U.Ui.state(u), "mail.on", "off"), "on"))), "Filed; automation paused", "Filed"),
    Bool.pick(String, String.eq(state, "ack"), "Acknowledged; waiting for committed message", Bool.pick(String, String.eq(state, "sending"), "Sending; draft preserved", Bool.pick(String, String.eq(state, "unknown"), "Outcome unknown; check the conversation before sending again. Draft preserved.", MA.get(u, "error")))))


def MA.after(a: U.Act) -> U.Act:
  match a:
    case U.Act{u, cs}: U.Act{MA.reconcile(u), cs}



def MA.fields() -> List<&2, String>:
  ["state", "text", "to", "previous", "error", "draft"]

def MA.snapshot.fields(fs: List<&2, String>, +u: U.Ui) -> List<&2, J.KV>:
  match fs:
    case Nil{}: Nil{}
    case +f <> rest: J.KV{f, J.Str{MA.get(u, f)}} <> MA.snapshot.fields(rest, u)

def MA.snapshot(+u: U.Ui) -> String:
  J.Json.show(J.Json.obj(MA.snapshot.fields(MA.fields(), MA.put(u, "draft", U.Ui.scratch(u, "@f.mrreply")))))

def MA.restore.fields(fs: List<&2, String>, +j: J.Json, u: U.Ui) -> U.Ui:
  match fs:
    case Nil{}: u
    case +f <> rest: MA.restore.fields(rest, j, MA.put(u, f, J.Json.get_str(j, f, "")))

def MA.restore(+u: U.Ui, text: String) -> U.Ui:
  +next = MA.restore.fields(MA.fields(), Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{}), u)
  U.Ui.scratch_set(MA.online(next, False{}), "@f.mrreply", MA.get(next, "draft"))
