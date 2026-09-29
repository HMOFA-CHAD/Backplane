import Base
import ./check.bend as C
import ../src/core/json.bend as J
import ../src/core/model.bend as M
import ../src/core/desk.bend as DK
import ../src/mobile/notify.bend as N
import ../src/core/client.bend as U

# Desks (core/desk.bend): the window or a web page watching a thread holds
# the phones' alerts for it; the desk used last gets a desktop notification
# for the rest.

def show.to(m: Maybe<&2, U32>) -> String:
  match m:
    case Some{c}:
      U32.show(c)
    case None{}:
      "none"

# client 1: the web page, focused on t1 since 100; client 2: the window,
# not focused, last used at 150; client 3: a phone
def looks() -> List<&2, DK.At>:
  [DK.At{1, DK.Look{True{}, "t1", True{}, 100n}}, DK.At{2, DK.Look{True{}, "t2", False{}, 150n}}, DK.At{3, DK.Look.none()}]

def state() -> M.State:
  M.State.replay([M.ThreadCreated{"tw", "", "Watched work", M.Local{}, "", "", "claude", "", 100n},
    M.MessagePosted{"tw", "u1", M.User{}, "go", 100n}, M.TurnChanged{"tw", M.Running{}, 100n},
    M.MessagePosted{"tw", "m1", M.Assistant{}, "Done.", 110n}, M.TurnChanged{"tw", M.Completed{}, 110n}], M.State.empty())

def ph.alerts(+desk: String) -> String:
  Nat.show(List.length(&2, J.Json, N.Note.alerts(U.Ui.threads(state()), [N.Seen{"tw", True{}}], state(), M.State.entries.all(state()), desk)))

def cmds(a: U.Act) -> List<&2, U.Cmd>:
  match a:
    case U.Act{_, cs}:
      cs

def sent(a: U.Act) -> String:
  Nat.show(List.length(&2, U.Cmd, cmds(a)))

def ui(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}:
      u

def cmd.show(cs: List<&2, U.Cmd>) -> String:
  match cs:
    case U.Notify{th, ti, b, k} <> _:
      th ++ "|" ++ ti ++ "|" ++ b ++ "|" ++ k
    case U.Send{t} <> _:
      t
    case _:
      ""

def main() -> IO(Unit):
  do IO<Unit>:
    # who watches
    C.Check.str("focused desk watches its thread", DK.Desk.text(looks(), 200n), "t1")
    C.Check.str("a look runs out", DK.Desk.text(looks(), 280n), "")
    C.Check.str("watched thread: no desktop notification", show.to(DK.Desk.to(looks(), "t1", 200n)), "none")
    C.Check.str("other thread: the desk used last", show.to(DK.Desk.to(looks(), "t9", 200n)), "2")
    C.Check.str("ran out: the desk used last", show.to(DK.Desk.to(looks(), "t1", 400n)), "2")
    C.Check.str("no desk: nowhere", show.to(DK.Desk.to([DK.At{3, DK.Look.none()}], "t1", 200n)), "none")
    C.Check.str("push held when watched", DK.Desk.hold(DK.Desk.seen(looks(), "t1", 200n), "turn-t1"), "")
    C.Check.str("push kept otherwise", DK.Desk.hold(DK.Desk.seen(looks(), "t9", 200n), "turn-t9"), "turn-t9")
    C.Check.str("watched names whole ids", Bool.show(DK.Desk.watched("t10\nt2", "t1")) ++ " " ++ Bool.show(DK.Desk.watched("t10\nt2", "t2")), "False True")
    # the phone's own alerts
    C.Check.str("phone alerts when no desk watches", ph.alerts(""), "1")
    C.Check.str("phone holds a watched thread", ph.alerts("t1\ntw"), "0")
    # the desk's side: said at once, again only on a change or a beat
    +a1 : U.Act = U.Ui.desk(U.Ui.select.k(U.Ui.init(1000n), "tw"), True{}, 1000n)
    C.Check.str("desk says its look at once", cmd.show(cmds(a1)), "{\"id\":0,\"m\":\"desk.look\",\"p\":{\"thread\":\"tw\",\"focused\":true}}")
    C.Check.str("not again within a beat", sent(U.Ui.desk(ui(a1), True{}, 1030n)), "0")
    C.Check.str("again after a beat", sent(U.Ui.desk(ui(a1), True{}, 1060n)), "1")
    C.Check.str("focus lost: said at once", sent(U.Ui.desk(ui(a1), False{}, 1001n)), "1")
    C.Check.str("unfocused: no beat", sent(U.Ui.desk(ui(U.Ui.desk(ui(a1), False{}, 1001n)), False{}, 1200n)), "0")
    C.Check.str("new connection: said again", sent(U.Ui.desk(U.Ui.online(ui(a1), True{}), True{}, 1001n)), "1")
    # a desktop notification from the hub becomes the host's command
    C.Check.str("notify reaches the host", cmd.show(cmds(U.Ui.recv_act(U.Ui.init(0n),
      J.Json.obj([J.KV{"t", J.Str{"notify"}}, J.KV{"thread", J.Str{"tw"}}, J.KV{"title", J.Str{"Watched work"}}, J.KV{"body", J.Str{"Done."}}, J.KV{"key", J.Str{"turn-tw"}}])))),
      "tw|Watched work|Done.|turn-tw")
