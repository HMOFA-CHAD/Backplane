import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/codec.bend as K
import ../src/core/json.bend as J
import ../src/core/client.bend as U
import ../src/core/botui.bend as BU
import ../src/core/far.bend as FR
import ../src/app/nui.bend as N
import ../src/core/bot.bend as BT
import ../src/mobile/hubs.bend as H

# Bots elsewhere in every client's one bot view (botui.bend's BU.head):
# a mirrored bot opens as a bot with its machine beside its name and the
# tabs its machine shares; a bot only reported by a linked machine is the
# same view with its chat alone; a phone paired with a bot's own hub and
# a hub that mirrors it shows the bot once, as its own hub's.

def items(cs: List<&2, M.Change>) -> List<&2, J.Json>:
  match cs:
    case Nil{}:
      Nil{}
    case c <> t:
      K.Change.encode(c) <> items(t)

def log(cs: List<&2, M.Change>) -> J.Json:
  J.Json.obj([J.KV{"t", J.Json.str("log")}, J.KV{"since", J.Json.nat(0n)}, J.KV{"items", J.Json.arr(items(cs))}])

def info(+remote: String) -> J.Json:
  J.Json.obj([J.KV{"t", J.Json.str("info")}, J.KV{"info", J.Json.obj([J.KV{"bots.remote", J.Json.str(remote)}])}])

def numbered(cs: List<&2, M.Change>, +n: Nat) -> List<&2, FR.Item>:
  match cs:
    case Nil{}:
      Nil{}
    case c <> t:
      FR.Item{n, K.Change.wire(c)} <> numbered(t, 1n+n)

def far(away: Bool) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(FR.Fr.msg("p1", "box", away, 0n, 12n,
    numbered([M.ThreadCreated{"bt1", "", "Kit", M.Local{}, "", "", "claude", "", 100n}, M.BotSet{"b1", "Kit", "bt1", 7n, "helps", 100n}], 11n))), J.Null{})

# this hub (lap) is linked to box (p1); box shares Kit and reports Kit
# and Nori, whose threads it does not share
def here() -> List<&2, M.Change>:
  [M.PeerSet{"p1", "box", "http://box:3787", False{}, 50n},
   M.ThreadCreated{"t1", "", "Pip", M.Local{}, "", "", "claude", "", 90n}, M.BotSet{"b9", "Pip", "t1", 3n, "", 90n}]

def dir() -> String:
  "[{\"name\":\"Kit\",\"peer\":\"p1\",\"peerName\":\"box\",\"look\":7,\"state\":\"ready\"},{\"name\":\"Nori\",\"peer\":\"p1\",\"peerName\":\"box\",\"look\":3,\"state\":\"working\"}]"

def recv(+u: U.Ui, +o: J.Json) -> U.Ui:
  U.Ui.recv(u, o)

def joined() -> U.Ui:
  recv(recv(recv(U.Ui.init(1000n), log(here())), info(dir())), far(False{}))

def act_ui(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}:
      u

def go(+u: U.Ui, +a: String, +v: String) -> U.Ui:
  act_ui(U.Ui.act(u, a, v))

def rid(r: BU.BRow) -> String:
  match r:
    case BU.BRow{i, _, _, _, _, _, _, _, _, _}:
      i

def rows(rs: List<&2, BU.BRow>) -> String:
  match rs:
    case Nil{}:
      ""
    case +r <> t:
      rid(r) ++ ">" ++ BU.BU.act(r) ++ ">" ++ BU.BU.row.title(r) ++ ";" ++ rows(t)

def strs(xs: List<&2, String>) -> String:
  String.join(xs, ",")

def head(+h: BU.Head) -> String:
  BU.Head.title(h) ++ "|" ++ BU.Head.mood(h) ++ "|" ++ strs(BU.Head.tabs(h)) ++ "|" ++ BU.Head.tab(h) ++ "|" ++ Bool.show(BU.Head.viewer(h)) ++ "|" ++ Bool.show(BU.Head.owns(h))

def view(v: BU.View) -> String:
  match v:
    case BU.VThread{}:
      "thread"
    case BU.VBot{b}:
      "bot " ++ BT.Bot.id(b)
    case BU.VRoom{_}:
      "room"
    case BU.VRemote{id}:
      "remote " ++ id

# Phones: lap (the bot's own hub: Kit is b1 there) and box, which mirrors
# lap's bots over link p1 (the link's id is the same at both ends)
def lap() -> List<&2, M.Change>:
  [M.PeerSet{"p1", "box", "http://box:3787", False{}, 50n},
   M.ThreadCreated{"bt1", "", "Kit", M.Local{}, "", "", "claude", "", 100n}, M.BotSet{"b1", "Kit", "bt1", 7n, "helps", 100n}]

def box() -> List<&2, M.Change>:
  [M.PeerSet{"p1", "lap", "http://lap:3787", False{}, 50n},
   M.ThreadCreated{"t2", "", "Nori", M.Local{}, "", "", "claude", "", 90n}, M.BotSet{"b2", "Nori", "t2", 3n, "", 90n}]

def hub(+h: H.Hubs, +k: String, +o: J.Json) -> H.Hubs:
  H.Hubs.after(H.Hubs.recv(h, k, o))

def mirror() -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(FR.Fr.msg("p1", "lap", False{}, 0n, 12n,
    numbered([M.ThreadCreated{"bt1", "", "Kit", M.Local{}, "", "", "claude", "", 100n}, M.BotSet{"b1", "Kit", "bt1", 7n, "helps", 100n}], 11n))), J.Null{})

def paired(lapped: List<&2, M.Change>) -> H.Hubs:
  hub(hub(hub(H.Hubs.set(H.Hubs.init(0n, "c"), ["lap:3787", "box:3787"]), "lap:3787", log(lapped)), "box:3787", log(box())), "box:3787", mirror())

def only_box() -> H.Hubs:
  hub(hub(H.Hubs.set(H.Hubs.init(0n, "c"), ["box:3787"]), "box:3787", log(box())), "box:3787", mirror())

def jstrs(js: List<&2, J.Json>, +key: String) -> String:
  match js:
    case Nil{}:
      ""
    case j <> t:
      J.Json.get_str(j, key, "") ++ ";" ++ jstrs(t, key)

def jbools(js: List<&2, J.Json>, +key: String) -> String:
  match js:
    case Nil{}:
      ""
    case j <> t:
      Bool.show(J.Json.get_bool(j, key, False{})) ++ ";" ++ jbools(t, key)

def list(+h: H.Hubs, +key: String) -> String:
  jstrs(J.Json.elems(J.Json.get_obj(H.Hubs.screen(h), "bots")), key)

def pbot(+h: H.Hubs) -> J.Json:
  J.Json.get_obj(H.Hubs.screen(h), "bot")

def nori.arrives(+u: U.Ui) -> U.Ui:
  U.Ui.recv(u, Maybe.default(&2, J.Json, J.Json.parse(FR.Fr.msg("p1", "box", False{}, 12n, 14n,
      numbered([M.ThreadCreated{"nt", "", "Nori", M.Local{}, "", "", "claude", "", 103n}, M.BotSet{"nb", "Nori", "nt", 3n, "", 103n}], 13n))), J.Null{}))

def main() -> IO(Unit):
  do IO<Unit>:
    +u : U.Ui = joined()
    C.Check.str("rows: mirrored opens as a bot, reported only as a conversation", rows(BU.BU.rows(u)),
      "b9>bot>Pip;p1~b1>bot>Kit · box;Nori@box>remote>Nori · box;")
    # the mirrored bot, chosen from its row or its report
    +k : U.Ui = go(u, "bot", "p1~b1")
    C.Check.str("mirrored bot shown as a bot", view(BU.BU.view(k)), "bot p1~b1")
    C.Check.str("its header", head(BU.BU.head(k, BU.BU.view(k))), "Kit · box|idle|chat,space,memory,routines|chat|False|False")
    C.Check.str("remote action opens the mirror", view(BU.BU.view(go(u, "remote", "Kit@box"))), "bot p1~b1")
    C.Check.str("a tab it lacks falls back to chat", BU.BU.tab.of(go(k, "bot-tab", "browser"), "p1~b1") ++ " " ++ BU.BU.tab.of(go(k, "bot-tab", "memory"), "p1~b1"), "chat memory")
    C.Check.str("a bot here keeps every tab", head(BU.BU.head(go(u, "bot", "b9"), BU.BU.view(go(u, "bot", "b9")))), "Pip|sleep|chat,space,browser,memory,routines,hooks,settings|chat|True|True")
    C.Check.str("away while its machine is", head(BU.BU.head(recv(k, far(True{})), BU.BU.view(recv(k, far(True{}))))), "Kit · box (away)|away|chat,space,memory,routines|chat|False|False")
    # a bot only reported: the bot view with its chat alone
    +n : U.Ui = go(u, "remote", "Nori@box")
    C.Check.str("reported only: the conversation", view(BU.BU.view(n)), "remote Nori@box")
    +arrived : U.Ui = nori.arrives(n)
    C.Check.str("reported choice adopts its arriving mirrored thread", U.Ui.scratch(arrived, "@bot") ++ " " ++ U.Ui.sel(arrived) ++ " [" ++ U.Ui.scratch(arrived, "@remote") ++ "]", "p1~nb p1~nt []")
    C.Check.str("arriving thread keeps native keyboard focus", N.Nui.focus_of(N.Nui.unremote(N.Nui.with_focus(N.Nui.init(arrived, 1400, 900), N.Fld.alias("remote-send")))), "composer")
    +writing : U.Ui = nori.arrives(go(n, "bfield", "rtext\u{1f}unfinished"))
    C.Check.str("arrival preserves an unfinished composer", U.Bots.field(writing, "rtext") ++ " " ++ U.Ui.scratch(writing, "@remote"), "unfinished Nori@box")
    C.Check.str("its header", head(BU.BU.head(n, BU.BU.view(n))), "Nori · box|work|chat|chat|False|False")
    C.Check.str("one no machine lists", head(BU.BU.head(u, BU.VRemote{"Ghost@far"})), "Ghost@far|away|chat|chat|False|False")
    # phones: the row's action and the bot's header
    C.Check.str("phone rows act", list(only_box(), "act"), "bot;bot;")
    C.Check.str("phone rows keep remote", jbools(J.Json.elems(J.Json.get_obj(H.Hubs.screen(only_box()), "bots")), "remote"), "False;True;")
    C.Check.str("phone row titles", list(only_box(), "title"), "Nori;Kit · lap;")
    +pb : H.Hubs = H.Hubs.after(H.Hubs.act(only_box(), "bot", "box:3787|p1~b1"))
    C.Check.str("phone bot header", J.Json.get_str(pbot(pb), "title", "") ++ " " ++ jstrs(J.Json.elems(J.Json.get_obj(pbot(pb), "tabs")), "id") ++ " " ++ J.Json.show(J.Json.get_obj(pbot(pb), "edit")),
      "Kit · lap chat;space;memory;routines; false")
    +pr : H.Hubs = H.Hubs.after(H.Hubs.act(only_box(), "remote", "box:3787|Ghost@far"))
    C.Check.str("phone reported bot header", J.Json.get_str(pbot(pr), "kind", "") ++ " " ++ J.Json.get_str(pbot(pr), "title", "") ++ " " ++ jstrs(J.Json.elems(J.Json.get_obj(pbot(pr), "tabs")), "id"),
      "remote Ghost@far chat;")
    # paired with both: Kit once, as lap's own
    C.Check.str("paired with both: each bot once, as its own hub's", list(paired(lap()), "id"), "lap:3787|b1;box:3787|b2;")
    C.Check.str("even when its hub has no bot of that name", list(paired([M.PeerSet{"p1", "box", "http://box:3787", False{}, 50n}]), "id"), "box:3787|b2;")
