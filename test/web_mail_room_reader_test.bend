import Base
import ./check.bend as C
import ./web_mail_room_nodes.bend as W
import ../src/web/mail-actions.bend as MA
import ../src/web/mailroom.bend as WM
import ../src/web/dom.bend as D
import ../src/core/client.bend as U
import ../src/core/json.bend as J

# test/tools/web_mail_room_reader.mjs invokes these exports after emission,
# not main; main below runs the same checks for scripts/test.sh.
def preferred(parts: List<&2, String>, owner: String) -> String:
  MA.MA.participant(parts, owner)

def hint(loading: Bool, failed: Bool, has_messages: Bool) -> String:
  WM.WM.read_hint(loading, failed, has_messages)

def reader() -> D.Node:
  WM.WM.conversation(U.Ui.scratch_set(U.Ui.init(1n), "@mr.conv", "room:fixture"))

def act_ui(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}: u

def pending(other_error: String) -> U.Ui:
  act_ui(U.Mailv.read(MA.MA.put(U.Ui.scratch_set(U.Ui.init(1n), "@mr.conv", "room:fixture"), "error", other_error), ""))

def request_again(u: U.Ui) -> U.Ui:
  act_ui(U.Mailv.read(u, ""))

def read_id(u: U.Ui) -> String:
  U.Ui.scratch(u, "@mr.read")

def respond(+u: U.Ui, id: String, ok: Bool, error: String) -> U.Ui:
  +o = J.Json.obj([J.KV{"t", J.Str{"reply"}}, J.KV{"id", J.Str{id}}, J.KV{"ok", J.Flag{ok}}, J.KV{"error", J.Str{error}},
    J.KV{"result", J.Json.obj([J.KV{"conv", J.Json.obj([J.KV{"id", J.Str{U.Ui.scratch(u, "@mr.conv")}}, J.KV{"parts", J.Json.arr(Nil{})}])}, J.KV{"mails", J.Json.arr(Nil{})}])}])
  U.Mailv.reply(MA.MA.recv(u, o), o)

def page(u: U.Ui) -> D.Node:
  WM.WM.page(u)

def reader_from(u: U.Ui) -> D.Node:
  WM.WM.conversation(u)

def other_conversation(u: U.Ui) -> U.Ui:
  U.Ui.scratch_set(u, "@mr.conv", "room:other")

# The checks of test/tools/web_mail_room_reader.mjs, run here so scripts/test.sh
# runs them too.
def status_of(n: D.Node) -> String:
  W.Wn.key_head(n, "mail-read-status")

def error_of(n: D.Node) -> String:
  W.Wn.key_head(n, "mail-error")

def flags(loading: Bool, failed: Bool) -> String:
  "{\"loading\":" ++ Bool.pick(String, loading, "true", "false") ++ ",\"failed\":" ++ Bool.pick(String, failed, "true", "false") ++ "}"

def missing(loading: Bool, failed: Bool) -> String:
  Bool.pick(String, loading, "Loading message bodies…", Bool.pick(String, failed, "Messages could not be loaded. See the mail error above.", "No message bodies were returned for this conversation."))

def hints(+loading: Bool, +failed: Bool) -> IO(Unit):
  do IO<Unit>:
    C.Check.str("existing bodies stay visible " ++ flags(loading, failed), hint(loading, failed, True{}), "")
    C.Check.str("missing body state " ++ flags(loading, failed), hint(loading, failed, False{}), missing(loading, failed))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("receiver prefers owner after another bot", preferred(["bot:first", "bot:owner"], "owner"), "owner")
    C.Check.str("receiver prefers owner after person and multiple bots", preferred(["person", "bot:first", "thread:other", "bot:owner"], "owner"), "owner")
    C.Check.str("receiver falls back first bot when owner is absent", preferred(["person", "thread:other", "bot:first", "bot:second"], "owner"), "first")
    C.Check.str("receiver remains empty without any bot participant", preferred(["person", "thread:other"], "owner"), "")
    C.Check.str("receiver remains empty for no participants", preferred(Nil{}, "owner"), "")
    hints(False{}, False{})
    hints(False{}, True{})
    hints(True{}, False{})
    hints(True{}, True{})
    C.Check.str("production reader exposes polite status", W.Wn.key_pick(reader(), "mail-read-status", "role", "aria-live"), "role=status,aria-live=polite")
    C.Check.str("production reader renders truthful no-body text", status_of(reader()), "No message bodies were returned for this conversation.")
    +p : U.Ui = pending("Previous send failed")
    C.Check.str("actual pending state renders loading", status_of(reader_from(p)), "Loading message bodies…")
    +rid : String = read_id(p)
    +empty : U.Ui = respond(p, rid, True{}, "")
    C.Check.str("successful empty read is not mislabelled by prior send error", status_of(reader_from(empty)), "No message bodies were returned for this conversation.")
    C.Check.str("prior send error remains visible separately", error_of(page(empty)), "Previous send failed")
    +failed : U.Ui = respond(p, rid, False{}, "Body store unavailable")
    C.Check.str("actual correlated read failure renders failure status", status_of(reader_from(failed)), "Messages could not be loaded. See the mail error above.")
    C.Check.str("actual backend error remains visible", error_of(page(failed)), "Body store unavailable · Previous send failed")
    +again : U.Ui = request_again(failed)
    +recovered : U.Ui = respond(again, read_id(again), True{}, "")
    C.Check.str("successful retry clears only read failure", error_of(page(recovered)), "Previous send failed")
    C.Check.str("successful retry empty result remains truthful", status_of(reader_from(recovered)), "No message bodies were returned for this conversation.")
    +stale : U.Ui = respond(request_again(pending("")), rid, False{}, "Stale read failure")
    C.Check.str("old read response cannot fail current pending read", status_of(reader_from(stale)), "Loading message bodies…")
    C.Check.str("old read failure is not attached to current conversation", error_of(page(stale)), "")
    C.Check.str("different conversation does not inherit read error", error_of(page(respond(other_conversation(pending("")), rid, False{}, "Other conversation failure"))), "")
