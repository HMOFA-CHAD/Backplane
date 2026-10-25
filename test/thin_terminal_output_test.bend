import Base
import ./check.bend as C
import ./thin_terminal_input_test.bend as F
import ../src/server/thin-actor.bend as A
import ../src/server/thin-view.bend as V
import ../src/server/terminal-output.bend as O
import ../src/core/client.bend as U
import ../src/core/json.bend as J
import ../src/web/app.bend as W
import ../src/web/workspace.bend as WS
import ../src/web/presentation.bend as P

def ui() -> U.Ui:
  U.Ui.info_set(U.Ui.info_set(U.Ui.info_set(F.ui(), "local.terminal.output", "pane-v1"), "local.terminal.incarnation", "1"), "local.terminal.pid", "42")

def actor() -> A.Actor:
  A.Actor.make(ui(), "v", V.Target.json("thread", "a"))

def output() -> J.Json:
  F.obj("{\"t\":\"term\",\"thread\":\"a\",\"pid\":42,\"b\":[90]}")

def fed() -> A.Actor:
  A.Actor.message(actor(), True{}, "h", output())

def reply_actor(ok: Bool) -> A.Actor:
  +cmd = J.Json.obj([J.KV{"type", J.Str{"send"}}, J.KV{"text", J.Str{"{\"id\":101,\"m\":\"term.input\",\"p\":{\"thread\":\"a\",\"b\":[97]}}"}}])
  +a = A.Actor.accept(actor(), V.ActResult{ui(), [cmd]}, False{})
  A.Actor.message(a, True{}, "h", J.Json.obj([J.KV{"t", J.Str{"reply"}}, J.KV{"id", J.Json.nat(101n)}, J.KV{"ok", J.Flag{ok}}, J.KV{"error", J.Str{Bool.pick(String, ok, "", "fixture error")}}]))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("exact live floating output opt-in", Bool.show(O.Output.enabled(True{}, ui(), "a")), "True")
    C.Check.str("native retains normal renderer", Bool.show(O.Output.enabled(False{}, ui(), "a")), "False")
    C.Check.str("absent output opt-in keeps old path", Bool.show(O.Output.enabled(True{}, F.ui(), "a")), "False")
    C.Check.str("unknown output opt-in keeps old path", Bool.show(O.Output.enabled(True{}, U.Ui.info_set(ui(), "local.terminal.output", "pane-v2"), "a")), "False")
    C.Check.str("other owner cannot push", Bool.show(O.Output.enabled(True{}, ui(), "b")), "False")
    C.Check.str("hidden popup cannot push", Bool.show(O.Output.enabled(True{}, U.Ui.flag_off(ui(), "term"), "a")), "False")
    C.Check.str("floating bytes do not dirty conversation", Bool.show(A.Actor.dirty(fed())), "False")
    C.Check.str("legacy output still invalidates view", Bool.show(A.Actor.dirty(A.Actor.message(A.Actor.make(F.ui(), "v", V.Target.json("thread", "a")), True{}, "h", output()))), "True")
    C.Check.str("existing dirtiness survives terminal output", Bool.show(A.Actor.dirty(A.Actor.message(A.Actor.mark_dirty(actor()), True{}, "h", output()))), "True")
    C.Check.str("output advances private watermark", U.Ui.info(A.Actor.ui(fed()), "local.terminal.sequence"), "1")
    C.Check.str("output retains actual process identity", U.Ui.info(A.Actor.ui(fed()), "local.terminal.pid"), "42")
    C.Check.str("unrelated terminal cannot feed actor", U.Ui.info(A.Actor.ui(A.Actor.message(actor(), True{}, "h", F.obj("{\"t\":\"term\",\"thread\":\"b\",\"pid\":43,\"b\":[90]}"))), "local.terminal.sequence"), "")
    C.Check.str("pending coalesces behind offered frame", Bool.show(O.Output.pending(True{}, U.Ui.info_set(O.Output.next(ui()), "local.terminal.offered", "8"), "a", 7n)), "False")
    C.Check.str("writer completion releases latest pending pane", Bool.show(O.Output.pending(True{}, U.Ui.info_set(O.Output.next(ui()), "local.terminal.offered", "8"), "a", 8n)), "True")
    C.Check.str("offering clears one pending flag", U.Ui.info(O.Output.offered(O.Output.next(ui()), 8n), "local.terminal.pending"), "")
    C.Check.str("sequence exhaustion falls back instead of wrapping", Bool.show(O.Output.enabled(True{}, U.Ui.info_set(ui(), "local.terminal.sequence", "281474976710655"), "a")), "False")
    C.Check.str("new popup has new incarnation", U.Ui.info(U.Act.ui(WS.WS.term.show(True{}, ui(), "80x24")), "local.terminal.incarnation"), "2")
    C.Check.str("pane carries full-reply watermark", Bool.show(String.contains(J.Json.show(P.Node.write(W.terminal_node(A.Actor.ui(fed())))), "data-terminal-sequence")), "True")
    C.Check.str("pane carries popup incarnation", Bool.show(String.contains(J.Json.show(P.Node.write(W.terminal_node(ui()))), "data-terminal-incarnation")), "True")
    C.Check.str("successful matching input ACK does not redraw", Bool.show(A.Actor.dirty(reply_actor(True{}))), "False")
    C.Check.str("input failure remains actionable", Bool.show(A.Actor.dirty(reply_actor(False{}))), "True")
    C.Check.str("no command authority in pane", Bool.show(Maybe.is_some(&2, J.Json, J.Json.get(O.Output.message(A.Actor.ui(fed()), "a", "1", "epoch", "v", V.Target.json("thread", "a")), "cmds"))), "False")
