import Base
import ../src/web/mail-actions.bend as MA
import ../src/web/mailroom.bend as WM
import ../src/web/dom.bend as D
import ../src/core/client.bend as U
import ../src/core/json.bend as J

# The JS driver explicitly invokes these exports after emission. It does not
# mistake an emitted IO main for an executed check.
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
