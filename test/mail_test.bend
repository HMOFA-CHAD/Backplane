import Base
import ./check.bend as C
import ../src/core/mail.bend as ML
import ../src/core/model.bend as M
import ../src/core/codec.bend as CD
import ../src/core/json.bend as J
import ../src/core/hub.bend as H
import ../src/core/bothub.bend as BH
import ../src/core/client.bend as U
import ../src/core/far.bend as FR

# Codec, classification, folding, funnels, and the bounded page at scale.
def line(c: M.Change) -> String:
  J.Json.show(CD.Change.encode(c))

def decoded(m: Maybe<&2, M.Change>) -> String:
  match m:
    case Some{c}: line(c)
    case None{}: "none"

def round(c: M.Change) -> String:
  decoded(CD.Change.decode(CD.Change.encode(c)))

def missing(text: String) -> String:
  decoded(CD.Change.decode(Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{})))

def origin(o: ML.Origin) -> String:
  match o:
    case ML.Origin{from, kind, ref}: from ++ "|" ++ kind ++ "|" ++ ref

def ids(cs: List<&2, ML.Conv>) -> String:
  match cs:
    case Nil{}: ""
    case c <> rest: ML.Conv.id(c) ++ "," ++ ids(rest)

def mail(id: String, conv: String, from: String, to: String, at: Nat) -> M.Change:
  M.MailPosted{id, conv, from, to, "thread", "", "act", "Latest HEAD", 10n, at}

def msg_ids(cs: List<&2, M.Change>) -> String:
  match cs:
    case Nil{}: ""
    case M.MessagePosted{_, _, _, _, _} <> t: "posted," ++ msg_ids(t)
    case M.MessageFrom{_, _, _, kind, _, _} <> t: kind ++ "," ++ msg_ids(t)
    case _ <> t: msg_ids(t)

def step_cs(st: H.Step) -> List<&2, M.Change>:
  match st:
    case H.Step{cs, _}: cs

def run_live(r: Maybe<&2, ML.Run>) -> Bool:
  match r:
    case None{}: False{}
    case Some{r}: ML.Run.live(r)

def scale(+fuel: Nat, s: M.State) -> M.State:
  match fuel:
    case 0n: s
    case 1n+k:
      scale(k, M.State.apply(s, mail("m" ++ Nat.show(k), "c" ++ Nat.show(Nat.mod(k, 500n)), "thread:w", "bot:b" ++ Nat.show(Nat.mod(k, 5n)), Nat.sub(20000n, k))))

def scale_convs(+fuel: Nat, s: M.State) -> M.State:
  match fuel:
    case 0n: s
    case 1n+k:
      scale_convs(k, M.State.apply(s, M.ConvSet{"c" ++ Nat.show(k), "subject", "pair", "bot:b0\nbot:b1\nbot:b2\nbot:b3\nbot:b4", "p", "tag", 0n}))

def decisions(+fuel: Nat, b: ML.Box) -> ML.Box:
  match fuel:
    case 0n: b
    case 1n+k: decisions(k, ML.Box.decision(b, ML.Decision{Nat.show(k), "a", "c1", "run", "did", "because", k}))

def balanced(t: ML.Order) -> Bool:
  match t:
    case ML.OEmpty{}: True{}
    case ML.ONode{h, n, _, _, +l, +r}:
      Bool.and(Nat.is_eq(h, 1n+ML.Max(ML.Order.height(l), ML.Order.height(r))),
        Bool.and(Nat.is_eq(n, 1n+Nat.add(ML.Order.count(l), ML.Order.count(r))),
          Bool.and(Nat.is_le(ML.Order.height(l), 1n+ML.Order.height(r)),
            Bool.and(Nat.is_le(ML.Order.height(r), 1n+ML.Order.height(l)), Bool.and(balanced(l), balanced(r))))))

def long_text(n: Nat, +text: String) -> String:
  match n:
    case 0n: text
    case 1n+k: long_text(k, text ++ text)

def origin_at(+s: M.State, +thread: String, +msg: String) -> String:
  origin(Maybe.default(&2, ML.Origin, ML.Box.origin_of(M.State.mail(s), thread, msg), ML.Origin{"", "missing", ""}))

def mirrored(s: M.State, m: Maybe<&2, M.Change>) -> M.State:
  match m:
    case None{}: s
    case Some{c}: M.State.apply(s, c)

def main() -> IO(Unit):
  do IO<Unit>:
    +vMessageFrom : M.Change = M.MessageFrom{"thread", "msg", "from", "kind", "ref", 3n}
    C.Check.str("MessageFrom round trip", round(vMessageFrom), line(vMessageFrom))
    +vConvSet : M.Change = M.ConvSet{"id", "subject", "kind", "parts", "project", "tags", 3n}
    C.Check.str("ConvSet round trip", round(vConvSet), line(vConvSet))
    +vMailPosted : M.Change = M.MailPosted{"id", "conv", "from", "to", "kind", "ref", "want", "head", 3n, 3n}
    C.Check.str("MailPosted round trip", round(vMailPosted), line(vMailPosted))
    +vMailMarked : M.Change = M.MailMarked{"bot", "conv", "status", 3n, 3n, 3n}
    C.Check.str("MailMarked round trip", round(vMailMarked), line(vMailMarked))
    +vMailTagged : M.Change = M.MailTagged{"bot", "conv", "tags", 3n}
    C.Check.str("MailTagged round trip", round(vMailTagged), line(vMailTagged))
    +vRunSet : M.Change = M.RunSet{"thread", "bot", "conv", "mail", 3n}
    C.Check.str("RunSet round trip", round(vRunSet), line(vRunSet))
    +vCharterSet : M.Change = M.CharterSet{"bot", "text", "by", 3n}
    C.Check.str("CharterSet round trip", round(vCharterSet), line(vCharterSet))
    +vDecisionLogged : M.Change = M.DecisionLogged{"id", "bot", "conv", "run", "text", "reason", 3n}
    C.Check.str("DecisionLogged round trip", round(vDecisionLogged), line(vDecisionLogged))
    C.Check.str("MessageFrom defaults", missing("{\"$\":\"MessageFrom\"}"), "{\"$\":\"MessageFrom\",\"thread\":\"\",\"msg\":\"\",\"from\":\"\",\"kind\":\"\",\"ref\":\"\",\"at\":0}")
    C.Check.str("MailPosted defaults", missing("{\"$\":\"MailPosted\"}"), "{\"$\":\"MailPosted\",\"id\":\"\",\"conv\":\"\",\"from\":\"\",\"to\":\"\",\"kind\":\"\",\"ref\":\"\",\"want\":\"\",\"head\":\"\",\"size\":0,\"at\":0}")
    C.Check.str("classify 0", origin(ML.Mail.classify("", "m1", False{}, "hello")), "person|person|")
    C.Check.str("classify 1", origin(ML.Mail.classify("a", "t:a:m2", False{}, "hello")), "thread:a|thread|")
    C.Check.str("classify 2", origin(ML.Mail.classify("a", "t:a:lr-r2", False{}, "Finished work")), "thread:a|launch|")
    C.Check.str("classify 3", origin(ML.Mail.classify("a", "t:a:lr-r3", False{}, "Wake w1: changed")), "thread:a|wake|w1")
    C.Check.str("classify 4", origin(ML.Mail.classify("a", "t:a:m4", False{}, "[message from A in #staff]\nhi")), "thread:a|room|staff")
    C.Check.str("classify 5", origin(ML.Mail.classify("", "m5", False{}, "[routine: daily]\ngo")), "routine:daily|routine|daily")
    C.Check.str("classify 6", origin(ML.Mail.classify("", "m6", False{}, "[webhook: gh]\nbody")), "hook:gh|hook|gh")
    C.Check.str("classify 7", origin(ML.Mail.classify("backplane", "t:backplane:l7", True{}, "lost work")), "backplane|lost|")
    C.Check.str("classify 8", origin(ML.Mail.classify("c", "t:c:td-one", True{}, "task result")), "thread:c|task|")
    C.Check.str("classify 9", origin(ML.Mail.classify("", "c8", False{}, "Backplane restarted while you were working. Continue where you left off.")), "backplane|carry|")
    C.Check.str("classify 10", origin(ML.Mail.classify("", "m9", False{}, "[message from person@mac]\nhello")), "person|person|")
    C.Check.str("classify 11", origin(ML.Mail.classify("deploy", "t:deploy:lr-r9", False{}, "done")), "backplane|deploy|")
    C.Check.str("classify 12", origin(ML.Mail.classify("lock:build", "t:lock:build:lr-r9", False{}, "yours")), "backplane|lock|build")
    C.Check.str("classify 13", origin(ML.Mail.classify("bot:a", "m10", False{}, "direct")), "bot:a|bot|")
    C.Check.str("classify 14", origin(ML.Mail.classify("", "m11", True{}, "notice")), "backplane|system|")
    C.Check.str("remote direct preserves identity", origin(ML.Mail.classify("", "m-remote", False{}, "[message from Miso@mac]\nhi")), "peer:Miso@mac|peer|")
    C.Check.str("linked sender wins over person envelope", origin(ML.Mail.classify("a", "t:a:m12", False{}, "[message from person@mac]\nquoted")), "thread:a|thread|")
    C.Check.str("ordinary Wake text stays thread mail", origin(ML.Mail.classify("a", "t:a:m13", False{}, "Wake the runner")), "thread:a|thread|")
    C.Check.str("wake report needs colon", origin(ML.Mail.classify("a", "t:a:lr-r13", False{}, "Wake w1")), "thread:a|launch|")
    C.Check.str("wake report needs one id", origin(ML.Mail.classify("a", "t:a:lr-r14", False{}, "Wake the runner: please")), "thread:a|launch|")
    C.Check.str("route person", ML.Mail.route(ML.Origin{"thread:a", "person", "r"}, "bot:b"), "")
    C.Check.str("route thread", ML.Mail.route(ML.Origin{"thread:a", "thread", "r"}, "bot:b"), "pair:bot:b|thread:a")
    C.Check.str("route bot", ML.Mail.route(ML.Origin{"thread:a", "bot", "r"}, "bot:b"), "pair:bot:b|thread:a")
    C.Check.str("route room", ML.Mail.route(ML.Origin{"thread:a", "room", "r"}, "bot:b"), "room:r")
    C.Check.str("route launch", ML.Mail.route(ML.Origin{"thread:a", "launch", "r"}, "bot:b"), "launch:a")
    C.Check.str("route task", ML.Mail.route(ML.Origin{"thread:a", "task", "r"}, "bot:b"), "launch:a")
    C.Check.str("route wake", ML.Mail.route(ML.Origin{"thread:a", "wake", "r"}, "bot:b"), "wake:r")
    C.Check.str("route lost", ML.Mail.route(ML.Origin{"thread:a", "lost", "r"}, "bot:b"), "system:b")
    C.Check.str("route deploy", ML.Mail.route(ML.Origin{"thread:a", "deploy", "r"}, "bot:b"), "system:b")
    C.Check.str("route lock", ML.Mail.route(ML.Origin{"thread:a", "lock", "r"}, "bot:b"), "system:b")
    C.Check.str("route carry", ML.Mail.route(ML.Origin{"thread:a", "carry", "r"}, "bot:b"), "system:b")
    C.Check.str("route system", ML.Mail.route(ML.Origin{"thread:a", "system", "r"}, "bot:b"), "system:b")
    C.Check.str("route reminder", ML.Mail.route(ML.Origin{"thread:a", "reminder", "r"}, "bot:b"), "system:b")
    C.Check.str("route routine", ML.Mail.route(ML.Origin{"thread:a", "routine", "r"}, "bot:b"), "routine:r")
    C.Check.str("route hook", ML.Mail.route(ML.Origin{"thread:a", "hook", "r"}, "bot:b"), "hook:r")
    C.Check.str("route peer", ML.Mail.route(ML.Origin{"thread:a", "peer", "r"}, "bot:b"), "peer:thread:a:r")
    C.Check.str("person room envelope", origin(ML.Mail.classify("", "m", False{}, "[message from you in #staff]\nhello")), "person|room|staff")
    C.Check.str("peer person room envelope", origin(ML.Mail.classify("", "m", False{}, "[message from person@mac in #staff]\nhello")), "person|room|staff")
    C.Check.str("peer room envelope", origin(ML.Mail.classify("", "m", False{}, "[message from Miso@mac in #staff]\nhello")), "peer:mac|room|staff")
    C.Check.str("lock with actual Link.from", origin(ML.Mail.classify(M.Link.from("t:lock:build:lr-r9"), "t:lock:build:lr-r9", False{}, "Lock build is yours")), "backplane|lock|build")
    C.Check.str("pair symmetric", ML.Mail.route(ML.Origin{"thread:a", "thread", ""}, "bot:b"), ML.Mail.route(ML.Origin{"bot:b", "bot", ""}, "thread:a"))
    C.Check.str("legacy dm", ML.Mail.route(ML.Origin{"bot:a", "room", "dm:a:b"}, "bot:b"), "pair:bot:a|bot:b")
    C.Check.str("wake fallback", ML.Mail.route(ML.Origin{"thread:a", "wake", ""}, "bot:b"), "launch:a")
    C.Check.str("want row 0", ML.Mail.want("launch", "", ML.Flags{"completed", False{}, False{}, False{}}), "fyi")
    C.Check.str("want row 1", ML.Mail.want("launch", "", ML.Flags{"failed", False{}, False{}, False{}}), "act")
    C.Check.str("want row 2", ML.Mail.want("launch", "", ML.Flags{"ask", False{}, False{}, False{}}), "act")
    C.Check.str("want row 3", ML.Mail.want("launch", "", ML.Flags{"loop", False{}, False{}, False{}}), "act")
    C.Check.str("want row 4", ML.Mail.want("task", "", ML.Flags{"", True{}, False{}, False{}}), "act")
    C.Check.str("want row 5", ML.Mail.want("wake", "", ML.Flags{"", False{}, False{}, False{}}), "act")
    C.Check.str("want row 6", ML.Mail.want("lost", "", ML.Flags{"", False{}, False{}, False{}}), "act")
    C.Check.str("want row 7", ML.Mail.want("deploy", "", ML.Flags{"", True{}, False{}, False{}}), "act")
    C.Check.str("want row 8", ML.Mail.want("lock", "", ML.Flags{"", True{}, False{}, False{}}), "act")
    C.Check.str("want row 9", ML.Mail.want("deploy", "", ML.Flags{"", False{}, False{}, False{}}), "fyi")
    C.Check.str("want row 10", ML.Mail.want("routine", "", ML.Flags{"", False{}, False{}, False{}}), "act")
    C.Check.str("want row 11", ML.Mail.want("hook", "", ML.Flags{"", False{}, False{}, False{}}), "act")
    C.Check.str("want row 12", ML.Mail.want("thread", "", ML.Flags{"", False{}, True{}, False{}}), "act")
    C.Check.str("want row 13", ML.Mail.want("bot", "", ML.Flags{"", False{}, True{}, False{}}), "act")
    C.Check.str("want row 14", ML.Mail.want("room", "", ML.Flags{"", False{}, False{}, False{}}), "fyi")
    C.Check.str("want row 15", ML.Mail.want("room", "", ML.Flags{"", False{}, False{}, True{}}), "act")
    C.Check.str("want row 16", ML.Mail.want("person", "", ML.Flags{"", False{}, True{}, False{}}), "act")
    C.Check.str("want row 17", ML.Mail.want("person", "", ML.Flags{"", False{}, False{}, False{}}), "fyi")
    C.Check.str("explicit fyi wins", ML.Mail.want("thread", "fyi", ML.Flags{"", True{}, True{}, True{}}), "fyi")
    C.Check.str("explicit act wins", ML.Mail.want("room", "act", ML.Flags{"", False{}, False{}, False{}}), "act")
    C.Check.str("head sanitizes first line", ML.Mail.head("hé\t🙂\rthere\nsecond"), "hé 🙂 there")
    C.Check.str("head Unicode limit", Nat.show(String.length(ML.Mail.head(String.repeat("🙂", 200n)))), "160")
    +auto : ML.Box = ML.Box.mail(ML.Box.empty(), ML.Mail{"auto", "pair:bot:a|thread:w", "thread:w", "bot:a", "thread", "", "act", "hello", 5n, 1n})
    C.Check.str("missing conversation gets conversation kind", ML.Conv.kind(ML.Box.conv(auto, "pair:bot:a|thread:w")), "pair")
    +base : M.State = M.State.replay([
      M.ConvSet{"c1", "First", "pair", "bot:a\nbot:b", "p", "red", 1n},
      M.ConvSet{"c2", "Second", "pair", "bot:a", "q", "green", 1n},
      M.ConvSet{"c3", "Third", "pair", "bot:a\nbot:b", "p", "blue", 1n},
      mail("m1", "c1", "bot:a", "bot:b", 5n),
      mail("m2", "c2", "person", "bot:a", 9n),
      mail("m3", "c3", "person", "bot:a", 7n),
      mail("m4", "c1", "bot:a", "bot:b", 3n)], M.State.empty())
    +b : ML.Box = M.State.mail(base)
    C.Check.str("newest first, out of order mail keeps last", ids(ML.Box.slice(b, "a", 0n, 3n)), "c2,c3,c1,")
    C.Check.str("rank slice", ids(ML.Box.slice(b, "a", 1n, 1n)), "c3,")
    C.Check.str("slice empty beyond end", ids(ML.Box.slice(b, "a", 100n, 50n)), "")
    C.Check.str("counts per bot", Nat.show(ML.Box.unread(b, "a")) ++ "/" ++ Nat.show(ML.Box.unread(b, "b")) ++ "/" ++ Nat.show(ML.Box.unread_all(b)), "2/2/4")
    +changed : ML.Box = ML.Box.conv_set(b, "c1", "Renamed", "pair", ["bot:a"], "p", ["red"], 100n)
    C.Check.str("metadata keeps mail order", ids(ML.Box.slice(changed, "a", 0n, 3n)), "c2,c3,c1,")
    C.Check.str("removed participant leaves index", ids(ML.Box.slice(changed, "b", 0n, 3n)), "c3,")
    C.Check.str("removed participant decrements unread", Nat.show(ML.Box.unread_all(changed)), "3")
    +opened : M.State = M.State.replay([M.MailMarked{"a", "c2", "open", 9n, 0n, 10n}, M.MailMarked{"b", "c1", "done", 5n, 0n, 10n}], base)
    C.Check.str("open and done counters", Nat.show(ML.Box.unread_all(M.State.mail(opened))), "2")
    +new : M.State = M.State.apply(opened, mail("m5", "c1", "bot:a", "bot:b", 11n))
    C.Check.str("new mail reopens done", ML.Mark.status(ML.Box.mark_of(M.State.mail(new), "b", "c1")), "unread")
    C.Check.str("new mail exact counters", Nat.show(ML.Box.unread_all(M.State.mail(new))), "3")
    +dup : M.State = M.State.apply(new, mail("m5", "c1", "bot:a", "bot:b", 11n))
    C.Check.str("duplicate is no-op", Nat.show(ML.Conv.n(ML.Box.conv(M.State.mail(dup), "c1"))) ++ "/" ++ Nat.show(ML.Box.unread_all(M.State.mail(dup))), "3/3")
    C.Check.str("status and project filter", ids(ML.Box.list(b, "a", "unread", "p", 0n, 10n)), "c3,")
    C.Check.str("find subject ignoring case", ids(ML.Box.find(b, "a", "SECOND", 1n)), "c2,")
    C.Check.str("find tag", ids(ML.Box.find(b, "a", "BLUE", 5n)), "c3,")
    C.Check.str("find newest head", Nat.show(List.length(&2, ML.Conv, ML.Box.find(b, "a", "latest head", 2n))), "2")
    +late : M.State = M.State.apply(base, M.MailPosted{"late", "c2", "person", "bot:a", "thread", "", "fyi", "obsolete header", 10n, 2n})
    C.Check.str("find ignores late older head", ids(ML.Box.find(M.State.mail(late), "a", "obsolete", 2n)), "")
    C.Check.str("find part", Nat.show(List.length(&2, ML.Conv, ML.Box.find(b, "a", "BOT:B", 9n))), "2")
    +rooms : M.State = M.State.replay([
      M.BotSet{"a", "Alpha", "ta", 0n, "", 1n}, M.BotSet{"b", "Beta", "tb", 0n, "", 1n},
      M.RoomSet{"r", "Staff", "a\nb", 1n}, M.RoomPosted{"p1", "r", "you", "hello", 0n, 2n}, M.MailMarked{"b", "room:r", "done", 2n, 0n, 2n},
      M.RoomPosted{"p2", "r", "Alpha", "reply", 0n, 3n}], M.State.empty())
    C.Check.str("legacy room conversation", ML.Conv.kind(ML.Box.conv(M.State.mail(rooms), "room:r")), "room")
    C.Check.str("legacy room members", String.join(ML.Conv.parts(ML.Box.conv(M.State.mail(rooms), "room:r")), ","), "bot:a,bot:b,person")
    C.Check.str("legacy room unread", Nat.show(ML.Box.unread_all(M.State.mail(rooms))), "2")
    C.Check.str("legacy room senders", ML.Mail.from(Maybe.default(&2, ML.Mail, List.head(&2, ML.Mail, ML.Box.headers(M.State.mail(rooms), "room:r")), ML.Mail{"", "", "", "", "", "", "", "", 0n, 0n})), "bot:a")
    +dm : M.State = M.State.replay([
      M.BotSet{"a", "Alpha", "ta", 0n, "", 1n}, M.BotSet{"b", "Beta", "tb", 0n, "", 1n},
      M.RoomPosted{"dm1", "dm:Alpha:Beta", "Alpha", "hello", 0n, 2n}], M.State.empty())
    C.Check.str("legacy DM recipient is indexed", ids(ML.Box.slice(M.State.mail(dm), "b", 0n, 2n)), "room:dm:Alpha:Beta,")
    C.Check.str("legacy DM both participants", String.join(ML.Conv.parts(ML.Box.conv(M.State.mail(dm), "room:dm:Alpha:Beta")), ","), "bot:a,bot:b")
    C.Check.str("legacy DM recipient unread", Nat.show(ML.Box.unread(M.State.mail(dm), "a")) ++ "/" ++ Nat.show(ML.Box.unread(M.State.mail(dm), "b")), "0/1")
    +dm_reply : M.State = M.State.apply(dm, M.RoomPosted{"dm2", "dm:Alpha:Beta", "Beta", "reply", 0n, 3n})
    C.Check.str("legacy DM reply preserves recipients", Nat.show(ML.Box.unread_all(M.State.mail(dm_reply))), "2")
    +renamed : M.State = M.State.apply(dm, M.BotSet{"a", "Amber", "ta", 0n, "", 3n})
    C.Check.str("sender index follows rename and case", ML.Box.sender(M.State.mail(renamed), "aMBer"), "bot:a")
    C.Check.str("sender old name removed", ML.Box.sender(M.State.mail(renamed), "Alpha"), "Alpha")
    C.Check.str("sender id alias", ML.Box.sender(M.State.mail(renamed), "a"), "bot:a")
    C.Check.str("sender deletion removes aliases", ML.Box.sender(M.State.mail(M.State.apply(renamed, M.BotDeleted{"a", 4n})), "Amber"), "Amber")
    C.Check.str("person sender bypasses lookup", ML.Box.sender(M.State.mail(renamed), "you"), "person")
    +long_room : M.State = M.State.apply(dm, M.RoomPosted{"long", "dm:Alpha:Beta", "you", long_text(18n, "x"), 0n, 5n})
    C.Check.str("long room replay keeps full safe size", Nat.show(ML.Mail.size(Maybe.default(&2, ML.Mail, List.head(&2, ML.Mail, ML.Box.headers(M.State.mail(long_room), "room:dm:Alpha:Beta")), ML.Mail{"", "", "", "", "", "", "", "", 0n, 0n}))), "262144")
    +mirrored_origin : M.State = mirrored(M.State.empty(), FR.Fr.change("mac", M.MessageFrom{"ta", "t:tb:m1", "thread:tb", "thread", "", 2n}))
    C.Check.str("cross-machine origin ids agree", origin_at(mirrored_origin, "mac~ta", "t:mac~tb:m1"), "thread:mac~tb|thread|")
    C.Check.str("cross-machine origin bot address", FR.Fr.address("mac", "bot:b"), "bot:mac~b")
    C.Check.str("cross-machine sender returns home", FR.Fr.address("mac", "thread:mac~tb"), "thread:tb")
    C.Check.str("cross-machine person stays person", FR.Fr.address("mac", "person"), "person")
    C.Check.str("cross-machine origin shared like post", Bool.show(FR.Fr.shared(dm, M.MessageFrom{"ta", "m", "thread:tb", "thread", "", 2n})), Bool.show(FR.Fr.shared(dm, M.MessagePosted{"ta", "m", M.User{}, "hi", 2n})))
    C.Check.str("cross-machine origin same scope", FR.Fr.scope(dm, M.MessageFrom{"ta", "m", "thread:tb", "thread", "", 2n}), FR.Fr.scope(dm, M.MessagePosted{"ta", "m", M.User{}, "hi", 2n}))
    +runs : M.State = M.State.apply(base, M.RunSet{"run", "a", "c1", "m1", 10n})
    C.Check.str("run set live", Bool.show(run_live(ML.Box.run_of(M.State.mail(runs), "run"))), "True")
    +ended : M.State = M.State.apply(runs, M.TurnChanged{"run", M.Completed{}, 11n})
    C.Check.str("terminal ends run", Bool.show(run_live(ML.Box.run_of(M.State.mail(ended), "run"))) ++ "/" ++ Nat.show(ML.Box.live_n(M.State.mail(ended), "a")), "False/0")
    +replaced : M.State = M.State.replay([M.RunSet{"run2", "a", "c1", "m2", 11n}, M.TurnChanged{"run", M.Failed{}, 12n}], runs)
    C.Check.str("old terminal cannot clear replacement", ML.Box.live(M.State.mail(replaced), "a", "c1") ++ "/" ++ Nat.show(ML.Box.live_n(M.State.mail(replaced), "a")), "run2/1")
    +orig : M.State = M.State.apply(base, M.MessageFrom{"t", "m", "thread:a", "thread", "", 1n})
    C.Check.str("origin stored", Bool.show(Maybe.is_some(&2, ML.Origin, ML.Box.origin_of(M.State.mail(orig), "t", "m"))), "True")
    +hub : M.State = M.State.replay([M.ThreadCreated{"t", "", "Target", M.Local{}, "", "", "codex", "", 1n}], M.State.empty())
    C.Check.str("inbox kernel keeps delivery law", msg_ids(step_cs(H.Hub.inbox.id(hub, 2n, "a", "t", M.User{}, "hello", "t:a:m2"))), "posted,")
    C.Check.str("explicit-id production funnel posts origin", msg_ids(step_cs(H.Hub.inbox.from(hub, 2n, "a", "t", M.User{}, "hello", "t:a:m2"))), "posted,thread,")
    C.Check.str("inbox posts then origin", msg_ids(step_cs(H.Hub.inbox(hub, 2n, "a", "t", M.User{}, "hello"))), "posted,thread,")
    C.Check.str("carry posts then origin", msg_ids(step_cs(H.Carry.k(True{}, hub, 2n, "t"))), "posted,carry,")
    C.Check.str("bot inbox posts then origin", msg_ids(step_cs(BH.Bots.inbox(hub, 2n, "a", "t", "m", "hello"))), "posted,thread,")
    C.Check.str("mail touch isolated", String.join(U.Touch.of(M.MailTagged{"a", "c", "tag", 1n}), ","), "@mail")
    C.Check.str("exact mail marker retained", U.Touch.id("@mail"), "@mail")
    C.Check.str("unknown mail prefix remains conservative", U.Touch.id("@mail.future"), "*")
    C.Check.str("mailbox is not the mail marker", U.Touch.id("@mailbox"), "*")
    C.Check.str("origin touches thread", String.join(U.Touch.of(M.MessageFrom{"t", "m", "thread:a", "thread", "", 1n}), ","), "t")
    C.Check.str("own bot chat has no origin even with envelope prefix", msg_ids(step_cs(BH.Bots.say.id("own", True{}, M.State.apply(hub, M.BotSet{"a", "Alpha", "t", 0n, "", 1n}), 2n, 0, "reply", "a", "[routine: daily]\nhello"))), "posted,")
    +meta : M.State = M.State.replay([M.CharterSet{"a", "Charter text", "person", 10n}, M.MailTagged{"a", "c1", "private\nwork", 10n}, M.DecisionLogged{"d", "a", "c1", "run", "Did it", "Requested", 10n}], base)
    C.Check.str("charter event folds", ML.Box.charter(M.State.mail(meta), "a"), "Charter text")
    C.Check.str("tag event folds", String.join(ML.Mark.tags(ML.Box.mark_of(M.State.mail(meta), "a", "c1")), ","), "private,work")
    C.Check.str("decision event folds", Nat.show(List.length(&2, ML.Decision, ML.Box.decisions(M.State.mail(meta), "a", 10n))), "1")
    +extras : ML.Box = ML.Box.tagged(ML.Box.charter_set(b, "a", "May inspect"), "a", "c1", ["mine"])
    C.Check.str("find per-bot tags", ids(ML.Box.find(extras, "a", "MINE", 2n)), "c1,")
    C.Check.str("charter", ML.Box.charter(extras, "a"), "May inspect")
    C.Check.str("tags preserve status and counters", String.join(ML.Mark.tags(ML.Box.mark_of(extras, "a", "c1")), ",") ++ "/" ++ Nat.show(ML.Box.unread_all(extras)), "mine/4")
    C.Check.str("decision tail capped", Nat.show(List.length(&2, ML.Decision, ML.Box.decisions(decisions(205n, extras), "a", 300n))), "200")
    +snoozed : ML.Box = ML.Box.marked(b, "a", "c2", "snoozed", 9n, 20n)
    C.Check.str("snoozed unread decremented", Nat.show(ML.Box.unread(snoozed, "a")), "1")
    C.Check.str("snoozed listing", ids(ML.Box.list(snoozed, "a", "snoozed", "", 0n, 10n)), "c2,")
    +start : Nat <- IO.now()
    +big : M.State = scale(20000n, scale_convs(500n, M.State.empty()))
    +page : String = ids(ML.Box.slice(M.State.mail(big), "b0", 0n, 50n))
    C.Check.str("scale top 50 has 50 rows", Nat.show(List.length(&2, ML.Conv, ML.Box.slice(M.State.mail(big), "b0", 0n, 50n))), "50")
    C.Check.str("scale newest conversation", String.take(page, 3n), "c0,")
    C.Check.str("scale exact unread total", Nat.show(ML.Box.unread_all(M.State.mail(big))), "2500")
    C.Check.str("scale deep rank slice", String.take(ids(ML.Box.slice(M.State.mail(big), "b0", 450n, 1n)), 5n), "c450,")
    C.Check.str("scale AVL metadata and balance", Bool.show(balanced(ML.Box.order_of(M.State.mail(big), "b0"))), "True")
    +end : Nat <- IO.now()
    IO.print("scale 20000 mails / 500 conversations / 5 bots + slice 50: " ++ Nat.show(Nat.sub(end, start)) ++ " ms")
