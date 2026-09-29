import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/codec.bend as K
import ../src/core/json.bend as J
import ../src/core/client.bend as U
import ../src/core/botui.bend as BU
import ../src/core/bot.bend as BT
import ../src/core/far.bend as FR

# Threads elsewhere (far.bend): a hub's clients fold a linked machine's
# bots and threads in under ids of their own, once, in order, and send
# what they do to them back to that machine.

def items(cs: List<&2, M.Change>) -> List<&2, J.Json>:
  match cs:
    case Nil{}:
      Nil{}
    case c <> t:
      K.Change.encode(c) <> items(t)

def log(+since: Nat, cs: List<&2, M.Change>) -> J.Json:
  J.Json.obj([J.KV{"t", J.Json.str("log")}, J.KV{"since", J.Json.nat(since)}, J.KV{"items", J.Json.arr(items(cs))}])

def info(+remote: String) -> J.Json:
  J.Json.obj([J.KV{"t", J.Json.str("info")}, J.KV{"info", J.Json.obj([J.KV{"bots.remote", J.Json.str(remote)}])}])

# items numbered from n, as the owning hub numbers its log
def numbered(cs: List<&2, M.Change>, +n: Nat) -> List<&2, FR.Item>:
  match cs:
    case Nil{}:
      Nil{}
    case c <> t:
      FR.Item{n, K.Change.wire(c)} <> numbered(t, 1n+n)

def far(+since: Nat, +head: Nat, away: Bool, xs: List<&2, FR.Item>) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(FR.Fr.msg("p1", "box", away, since, head, xs)), J.Null{})

# box's Kit: its thread (no project), a message, a turn that ran
def box() -> List<&2, FR.Item>:
  numbered([M.ThreadCreated{"bt1", "", "Kit", M.Local{}, "", "", "claude", "", 100n},
    M.BotSet{"b1", "Kit", "bt1", 7n, "helps", 100n},
    M.MessagePosted{"bt1", "m1", M.User{}, "hello", 101n},
    M.TurnChanged{"bt1", M.Running{}, 102n}], 11n)

def more() -> List<&2, FR.Item>:
  numbered([M.MessagePosted{"bt1", "m2", M.Assistant{}, "hi there", 103n}, M.TurnChanged{"bt1", M.Completed{}, 104n}], 20n)

def here() -> List<&2, M.Change>:
  [M.PeerSet{"p1", "box", "http://box:3787", False{}, 50n},
   M.ThreadCreated{"t1", "", "Pip", M.Local{}, "", "", "claude", "", 90n}, M.BotSet{"b9", "Pip", "t1", 3n, "", 90n}]

def recv(+u: U.Ui, +o: J.Json) -> U.Ui:
  U.Ui.recv(u, o)

def joined() -> U.Ui:
  recv(recv(recv(U.Ui.init(1000n), log(0n, here())), info("[{\"name\":\"Kit\",\"peer\":\"p1\",\"peerName\":\"box\",\"look\":7,\"state\":\"working\"}]")),
    far(0n, 14n, False{}, box()))

def title(t: M.Thread) -> String:
  match t:
    case M.Thread{_, _, ti, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      ti

def count(+u: U.Ui, +th: String) -> String:
  Nat.show(List.length(&2, M.Entry, M.State.mine(U.Ui.state(u), th)))

def rows(rs: List<&2, BU.BRow>) -> String:
  match rs:
    case Nil{}:
      ""
    case BU.BRow{+i, +n, _, _, +m, _, _, r, +p, +l} <> t:
      i ++ "|" ++ n ++ "|" ++ m ++ "|" ++ Bool.show(r) ++ "|" ++ p ++ "|" ++ l ++ ";" ++ rows(t)

def acts(rs: List<&2, BU.BRow>) -> String:
  match rs:
    case Nil{}:
      ""
    case +r <> t:
      BU.BU.act(r) ++ ";" ++ acts(t)

def act_ui(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}:
      u

def route(m: Maybe<&2, FR.Route>) -> String:
  match m:
    case Some{FR.Route{l, mm, b}}:
      l ++ " " ++ mm ++ " " ++ b
    case None{}:
      "none"

def rpc(+m: String, +p: List<&2, J.KV>) -> J.Json:
  J.Json.obj([J.KV{"id", J.Num{"7"}}, J.KV{"m", J.Str{m}}, J.KV{"p", J.Json.obj(p)}])

# the owning hub's state: Kit's thread and a project's thread
def owner() -> M.State:
  M.State.replay([M.ProjectCreated{"p", "board", "/b", 1n}, M.ThreadCreated{"pt", "p", "layout", M.Local{}, "", "", "claude", "", 2n},
    M.ThreadCreated{"bt1", "", "Kit", M.Local{}, "", "", "claude", "", 3n}, M.BotSet{"b1", "Kit", "bt1", 7n, "", 3n},
    M.AskOpened{"a1", "bt1", "tool", "Bash", "ls", "", 4n}, M.AskOpened{"a2", "pt", "tool", "Bash", "ls", "", 5n}], M.State.empty())

def main() -> IO(Unit):
  do IO<Unit>:
    +u : U.Ui = joined()
    C.Check.str("ids", FR.Fr.id("p1", "t~x") ++ " " ++ FR.Fr.link("p1~t~x") ++ " " ++ FR.Fr.local("p1~t~x") ++ " [" ++ FR.Fr.link("t1") ++ "] " ++ FR.Fr.local("t1"),
      "p1~t~x p1 t~x [] t1")
    C.Check.str("thread folded in under its link", count(u, "p1~bt1") ++ " " ++ title(U.Ui.thread(U.Ui.state(u), "p1~bt1")), "1 Kit")
    C.Check.str("its hub's sequence untouched", Nat.show(M.State.seq(U.Ui.state(u))), "3")
    C.Check.str("bot listed once, as a bot with its machine", rows(BU.BU.rows(u)),
      "b9|Pip|sleep|False||;p1~b1|Kit|work|True|box|p1;")
    C.Check.str("rows open as bots", acts(BU.BU.rows(u)), "bot;bot;")
    C.Check.str("title with its machine", U.Ui.far.title(u, "p1~bt1", "Kit") ++ "/" ++ U.Ui.far.title(u, "t1", "Pip"), "Kit · box/Pip")
    # the report of it (Kit@box) opens the mirrored bot, not a hub switch
    +s : U.Ui = act_ui(U.Ui.act(u, "remote", "Kit@box"))
    C.Check.str("remote pick opens the mirror", U.Ui.scratch(s, "@bot") ++ " " ++ U.Ui.sel(s) ++ " [" ++ U.Ui.scratch(s, "@remote") ++ "] [" ++ U.Ui.info(s, "local.machine") ++ "]",
      "p1~b1 p1~bt1 [] []")
    # the same batch again, and an older one, change nothing
    +u2 : U.Ui = recv(recv(u, far(0n, 14n, False{}, box())), far(10n, 13n, False{}, box()))
    C.Check.str("a batch twice is taken once", count(u2, "p1~bt1"), "1")
    # a batch past a gap is left for the pull
    +u3 : U.Ui = recv(u2, far(18n, 21n, False{}, more()))
    C.Check.str("a gap takes nothing", count(u3, "p1~bt1") ++ " " ++ Nat.show(FR.Fr.head(U.Ui.state(u3), "p1")), "1 14")
    +u4 : U.Ui = recv(u3, far(14n, 21n, False{}, more()))
    C.Check.str("the next batch in order", count(u4, "p1~bt1") ++ " " ++ Nat.show(FR.Fr.head(U.Ui.state(u4), "p1")), "2 21")
    # its machine stops answering: kept, away
    +u5 : U.Ui = recv(u4, far(21n, 21n, True{}, Nil{}))
    C.Check.str("away keeps it", count(u5, "p1~bt1") ++ " " ++ rows(BU.BU.rows(u5)) ++ " " ++ U.Ui.far.title(u5, "p1~bt1", "Kit"),
      "2 b9|Pip|sleep|False||;p1~b1|Kit|away|True|box|p1; Kit · box (away)")
    # a reconnect resumes this hub's log: the mirror stays; a fresh log
    # forgets it with its head, and the snapshot brings it back
    +u6 : U.Ui = recv(u5, log(3n, Nil{}))
    C.Check.str("resume keeps it", count(u6, "p1~bt1"), "2")
    +u7 : U.Ui = recv(u6, log(0n, here()))
    C.Check.str("fresh log forgets it", count(u7, "p1~bt1") ++ " " ++ Nat.show(FR.Fr.head(U.Ui.state(u7), "p1")), "0 0")
    +u8 : U.Ui = recv(u7, far(0n, 21n, False{}, List.append(&2, FR.Item, box(), more())))
    C.Check.str("snapshot again", count(u8, "p1~bt1"), "2")
    # requests: one about a thread elsewhere goes to its machine in its ids
    C.Check.str("route turn.start", route(FR.Fr.route(rpc("turn.start", [J.KV{"thread", J.Str{"p1~bt1"}}, J.KV{"text", J.Str{"hi"}}, J.KV{"msg", J.Str{"m9"}}]))),
      "p1 turn.start {\"id\":0,\"m\":\"turn.start\",\"p\":{\"thread\":\"bt1\",\"text\":\"hi\",\"msg\":\"m9\"}}")
    C.Check.str("route ask.answer", route(FR.Fr.route(rpc("ask.answer", [J.KV{"id", J.Str{"p1~a1"}}, J.KV{"answer", J.Str{"yes"}}]))),
      "p1 ask.answer {\"id\":0,\"m\":\"ask.answer\",\"p\":{\"id\":\"a1\",\"answer\":\"yes\"}}")
    C.Check.str("a request here stays", route(FR.Fr.route(rpc("turn.start", [J.KV{"thread", J.Str{"bt1"}}, J.KV{"text", J.Str{"a~b"}}]))), "none")
    # the owning hub: what it shares, and what it lets a linked machine do
    +st : M.State = owner()
    C.Check.str("shared", Bool.show(FR.Fr.shared(st, M.MessagePosted{"bt1", "m", M.User{}, "x", 9n})) ++ " " ++ Bool.show(FR.Fr.shared(st, M.MessagePosted{"pt", "m", M.User{}, "x", 9n}))
      ++ " " ++ Bool.show(FR.Fr.shared(st, M.SettingSet{"k", "v", 9n})) ++ " " ++ Bool.show(FR.Fr.shared(st, M.AskClosed{"a1", "y", 9n})) ++ " " ++ Bool.show(FR.Fr.shared(st, M.AskClosed{"a2", "y", 9n})),
      "True False False True False")
    C.Check.str("allowed", Bool.show(FR.Fr.allowed(st, rpc("turn.start", [J.KV{"thread", J.Str{"bt1"}}]))) ++ " " ++ Bool.show(FR.Fr.allowed(st, rpc("turn.start", [J.KV{"thread", J.Str{"pt"}}])))
      ++ " " ++ Bool.show(FR.Fr.allowed(st, rpc("ask.answer", [J.KV{"id", J.Str{"a1"}}]))) ++ " " ++ Bool.show(FR.Fr.allowed(st, rpc("ask.answer", [J.KV{"id", J.Str{"a2"}}])))
      ++ " " ++ Bool.show(FR.Fr.allowed(st, rpc("setting.set", [J.KV{"key", J.Str{"x"}}]))) ++ " " ++ Bool.show(FR.Fr.allowed(st, rpc("thread.delete", [J.KV{"thread", J.Str{"bt1"}}]))),
      "True False True False False False")
    # a mirrored bot's space page, served by the mirroring hub
    +pi : FR.In = FR.In.put(FR.In.new("p1", "box"), 0n, 3n, numbered([M.SpacePageSet{"b1", "<p>old</p>", 1n}, M.SpacePageSet{"b2", "<p>other</p>", 2n}, M.SpacePageSet{"b1", "<p>new</p>", 3n}], 1n))
    C.Check.str("mirrored space page", FR.In.page(pi, "b1") ++ "|" ++ FR.In.page(pi, "b9"), "<p>new</p>|")
