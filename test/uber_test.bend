import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/codec.bend as K
import ../src/core/json.bend as J
import ../src/core/uber.bend as UB

# The uberbot: its event, its codec and promotion (laws uber_*).

def base() -> List<&2, M.Change>:
  [M.ThreadCreated{"t1", "", "Kit", M.Local{}, "", "", "claude", "", 100n}, M.BotSet{"b1", "Kit", "t1", 7n, "", 100n},
    M.ThreadCreated{"t2", "", "Pip", M.Local{}, "", "", "claude", "", 101n}, M.BotSet{"b2", "Pip", "t2", 8n, "", 101n},
    M.ThreadCreated{"t3", "", "Far", M.Local{}, "", "", "claude", "", 102n}, M.BotSet{"p1~b9", "Far", "t3", 9n, "", 102n}]

def st(+extra: List<&2, M.Change>) -> M.State:
  M.State.replay(List.append(&2, M.Change, base(), extra), M.State.empty())

def yes(b: Bool) -> String:
  Bool.pick(String, b, "yes", "no")

def tags(cs: List<&2, M.Change>) -> String:
  match cs:
    case Nil{}:
      ""
    case c <> t:
      J.Json.get_str(K.Change.encode(c), "$", "") ++ ";" ++ tags(t)

def enc(m: Maybe<&2, M.Change>) -> String:
  match m:
    case Some{c}:
      J.Json.show(K.Change.encode(c))
    case None{}:
      "none"

def dec.k(m: Maybe<&2, J.Json>) -> Maybe<&2, M.Change>:
  match m:
    case Some{j}:
      K.Change.decode(j)
    case None{}:
      None{}

def dec(+s: String) -> Maybe<&2, M.Change>:
  dec.k(J.Json.parse(s))

def main() -> IO(Unit):
  do IO<Unit>:
    +c : M.Change = M.UberSet{"b1", "u5-ab", 9n}
    C.Check.str("round trip", yes(String.eq(J.Json.show(K.Change.encode(c)), "{\"$\":\"UberSet\",\"bot\":\"b1\",\"uid\":\"u5-ab\",\"at\":9}")), "yes")
    C.Check.str("decoded", enc(dec(J.Json.show(K.Change.encode(c)))), "{\"$\":\"UberSet\",\"bot\":\"b1\",\"uid\":\"u5-ab\",\"at\":9}")
    C.Check.str("a literal line", enc(dec("{\"$\":\"UberSet\",\"bot\":\"x\",\"uid\":\"u1-z\",\"at\":3}")), "{\"$\":\"UberSet\",\"bot\":\"x\",\"uid\":\"u1-z\",\"at\":3}")
    C.Check.str("none at first", UB.Uber.bot(st(Nil{})), "")
    C.Check.str("promote", tags(UB.Promo.log(UB.Uber.promote(st(Nil{}), "b1", "u1-a", 200n))), "UberSet;")
    +s1 : M.State = st([M.UberSet{"b1", "u1-a", 200n}])
    C.Check.str("is", UB.Uber.bot(s1), "b1")
    C.Check.str("is b1", yes(UB.Uber.is(s1, "b1")), "yes")
    C.Check.str("not b2", yes(UB.Uber.is(s1, "b2")), "no")
    C.Check.str("again changes nothing", tags(UB.Promo.log(UB.Uber.promote(s1, "b1", "u2-b", 300n))), "")
    C.Check.str("another bot", tags(UB.Promo.log(UB.Uber.promote(s1, "b2", "u2-b", 300n))), "UberSet;")
    C.Check.str("a far bot is refused", UB.Promo.err(UB.Uber.promote(st(Nil{}), "p1~b9", "u2-b", 300n)), "only a bot on this machine can be the uberbot")
    C.Check.str("nothing logged for it", tags(UB.Promo.log(UB.Uber.promote(st(Nil{}), "p1~b9", "u2-b", 300n))), "")
    C.Check.str("a missing bot is refused", tags(UB.Promo.log(UB.Uber.promote(st(Nil{}), "zz", "u2-b", 300n))), "")
    C.Check.str("demote", tags(UB.Promo.log(UB.Uber.promote(s1, "", "", 300n))), "UberSet;")
    C.Check.str("demote clears", UB.Uber.bot(st([M.UberSet{"b1", "u1-a", 200n}, M.UberSet{"", "", 300n}])), "")
    C.Check.str("demote with none", tags(UB.Promo.log(UB.Uber.promote(st(Nil{}), "", "", 300n))), "")
    C.Check.str("a deleted uberbot is none", UB.Uber.bot(st([M.UberSet{"b1", "u1-a", 200n}, M.BotDeleted{"b1", 250n}])), "")
    C.Check.str("a far id set is none", UB.Uber.bot(st([M.UberSet{"p1~b9", "u1-a", 200n}])), "")
    C.Check.str("uid", UB.Uber.uid(77n, "ff"), "u77-ff")
