import Base
import ./check.bend as C
import ../src/core/json.bend as J
import ../src/core/model.bend as M
import ../src/core/notice.bend as NO
import ../src/core/client.bend as U
import ../src/mobile/notify.bend as N
import ../src/mobile/screen.bend as S
import ../src/mobile/hubs.bend as H
import ../src/server/push.bend as P

def state(cs: List<&2, M.Change>) -> M.State:
  NO.Policy.demo.s(cs)

def cat(xss: List<&2, List<&2, M.Change>>) -> List<&2, M.Change>:
  NO.Policy.demo.cat(xss)

def thread(id: String) -> M.Change:
  NO.Island.compact.demo.thread(id)

def count(+s: M.State) -> String:
  Nat.show(NO.Island.compact.count(NO.Island.compact.demo.of(s)))

def chosen(+s: M.State) -> String:
  NO.Island.compact.id(NO.Island.compact.demo.of(s))

def phone(+s: M.State) -> J.Json:
  N.Note.compact(U.Ui.threads(s), s)

def hub(+s: M.State) -> J.Json:
  NO.Island.compact.json(P.Island.content(s), s)

def same(+s: M.State) -> String:
  Bool.show(String.eq(J.Json.show(hub(s)), J.Json.show(phone(s))))

def bot(extra: List<&2, M.Change>) -> M.State:
  state(cat([NO.Policy.demo.bot(), extra]))

def shown(+key: String, +s: M.State) -> H.Shown:
  H.Shown{key, key, J.Json.obj([J.KV{"island", phone(s)}, J.KV{"islandAt", J.Json.nat(NO.Island.compact.at(NO.Island.compact.demo.of(s)))}])}

def merged(ss: List<&2, H.Shown>) -> J.Json:
  H.Hubs.compact.go(ss, 0n, [], 0n)

def main() -> IO(Unit):
  do IO<Unit>:
    +five : M.State = NO.Island.compact.demo.five()
    +last : M.State = NO.Island.compact.demo.last()
    +kids : M.State = NO.Island.compact.demo.children()
    C.Check.str("five running roots", count(five), "5")
    C.Check.str("five roots still have one line", Nat.show(List.length(&2, J.Json, J.Json.elems(J.Json.get_obj(phone(five), "lines")))), "1")
    C.Check.str("the newest person message chooses the line", chosen(last), "t2")
    C.Check.str("launched and delegated children alone count zero", count(kids), "0")
    C.Check.str("hub and phone agree on five roots", same(five), "True")
    C.Check.str("hub and phone agree on latest send, despite a newer tool/link", same(last), "True")
    C.Check.str("hub and phone agree on children", same(kids), "True")
    C.Check.str("headline counts", NO.Island.compact.headline(0n) ++ "|" ++ NO.Island.compact.headline(1n) ++ "|" ++ NO.Island.compact.headline(5n), "All agents idle|1 running|5 running")
    +none : M.State = state([thread("t1"), M.TurnChanged{"t1", M.Running{}, 2n}])
    C.Check.str("a root without a personal message counts but has no line", J.Json.show(phone(none)), "{\"running\":1,\"headline\":\"1 running\",\"lines\":[]}")
    C.Check.str("hub and phone agree with no personal message", same(none), "True")
    +one : M.State = state(cat([[thread("t1")], NO.Policy.demo.run("t1", "m1", "go", 2n), [M.ActivityLogged{"t1", "a1", "tool", "edit", "file", 3n}]]))
    C.Check.str("the JSON shape and doing are shared", J.Json.show(phone(one)), "{\"running\":1,\"headline\":\"1 running\",\"lines\":[{\"thread\":\"t1\",\"title\":\"t1\",\"doing\":\"edit file\"}]}")
    C.Check.str("hub also supplies the same doing", same(one), "True")
    C.Check.str("bot room wake counts zero", count(bot(NO.Policy.demo.run("tb", "m1", "[message from Pebble in #ring] hi", 2n))), "0")
    C.Check.str("bot routine wake counts zero", count(bot(NO.Policy.demo.run("tb", "m1", "[routine: daily] go", 2n))), "0")
    C.Check.str("a personal bot turn counts", count(bot(NO.Policy.demo.run("tb", "m1", "hi", 2n))), "1")
    C.Check.str("an old personal message cannot make a linked bot wake count", count(bot(cat([NO.Policy.demo.run("tb", "m1", "hi", 2n), NO.Policy.demo.run("tb", M.Link.id("t1", "m2"), "hi", 2n)]))), "0")
    C.Check.str("queued personal bot message is not the current trigger", count(bot(cat([NO.Policy.demo.run("tb", "b1", "[message from Pebble] hi", 2n), [M.MessagePosted{"tb", "m2", M.User{}, "hi", 3n}, M.TurnQueued{"tb", "m2", "hi", 3n}]]))), "0")
    C.Check.str("archived roots are hidden", count(M.State.replay([M.ThreadArchived{"t1", True{}, 4n}], one)), "0")
    C.Check.str("deleted roots are hidden", count(M.State.replay([M.ThreadDeleted{"t1", 4n}], one)), "0")
    C.Check.str("mirrored roots count only on their owner hub", count(state(cat([[thread("box~t1")], NO.Policy.demo.run("box~t1", "m1", "hi", 2n)]))), "0")
    C.Check.str("background work alone is not running", count(state([thread("t1"), M.WorkSet{"t1", "bg", "a1\tbuild", 2n}])), "0")
    C.Check.str("unheard hub is empty", J.Json.show(N.Note.compact.json(N.Note.compact.of(False{}, U.Ui.threads(five), five), five)), "{\"running\":0,\"headline\":\"All agents idle\",\"lines\":[]}")
    +tie : M.State = state(cat([[thread("t1"), thread("t2")], NO.Policy.demo.run("t1", "m1", "hi", 2n), NO.Policy.demo.run("t2", "m2", "hi", 2n)]))
    C.Check.str("timestamp ties choose the smaller id", chosen(tie), "t1")
    C.Check.str("the tie is independent of input order", NO.Island.compact.id(NO.Island.compact.of([M.State.thread.get(tie, "t2"), M.State.thread.get(tie, "t1")], tie)), "t1")
    C.Check.str("paired counts include roots without lines", Nat.show(J.Json.get_nat(merged([shown("a", none), shown("b", last)]), "running", 0n)), "3")
    C.Check.str("paired hubs still select one line", Nat.show(List.length(&2, J.Json, J.Json.elems(J.Json.get_obj(merged([shown("a", five), shown("b", last)]), "lines")))), "1")
    C.Check.str("paired hubs choose by the latest direct send", J.Json.get_str(Maybe.default(&2, J.Json, List.head(&2, J.Json, J.Json.elems(J.Json.get_obj(merged([shown("a", five), shown("b", last)]), "lines"))), J.Null{}), "thread", ""), "t2")
    C.Check.str("per-hub naming preserves count without a line", J.Json.show(H.Hubs.island.named(True{}, "box", phone(none))), "{\"running\":1,\"headline\":\"1 running · box\",\"lines\":[]}")
