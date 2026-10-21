import Base
import ./check.bend as C
import ../src/core/thin-wire.bend as W
import ../src/core/thin.bend as T
import ../src/core/json.bend as J

def yes(b: Bool) -> String:
  Bool.pick(String, b, "yes", "no")

def obj(s: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(s), J.Null{})

def found(n: Maybe<&2, Nat>) -> String:
  match n:
    case None{}: "invalid"
    case Some{n}: Nat.show(n)

def target() -> J.Json:
  obj("{\"kind\":\"thread\",\"id\":\"a\"}")

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("ASCII byte limit exact", yes(W.Wire.within("abc", 3n)), "yes")
    C.Check.str("ASCII byte overflow refuses before saturated subtraction", yes(W.Wire.within("abcd", 3n)), "no")
    C.Check.str("Unicode scalar byte limit exact", yes(W.Wire.within("A日本😀", 11n)), "yes")
    C.Check.str("Unicode scalar overflow refuses", yes(W.Wire.within("A日本😀", 10n)), "no")
    C.Check.str("zero limit accepts empty only", yes(W.Wire.within("", 0n)), "yes")
    C.Check.str("zero limit refuses nonempty", yes(W.Wire.within("x", 0n)), "no")
    C.Check.str("target exact public object accepted", yes(W.Target.valid(target())), "yes")
    C.Check.str("target key order irrelevant", yes(W.Target.same(target(), obj("{\"id\":\"a\",\"kind\":\"thread\"}"))), "yes")
    C.Check.str("foreign target cannot match", yes(W.Target.same(target(), obj("{\"kind\":\"thread\",\"id\":\"b\"}"))), "no")
    C.Check.str("extra target authority fields rejected", yes(W.Target.valid(obj("{\"kind\":\"thread\",\"id\":\"a\",\"grant\":\"true\"}"))), "no")
    C.Check.str("empty recent target explicit", yes(W.Target.valid(obj("{\"kind\":\"recent\",\"id\":\"\"}"))), "yes")
    C.Check.str("empty thread ID refused", yes(W.Target.valid(obj("{\"kind\":\"thread\",\"id\":\"\"}"))), "no")
    C.Check.str("request exact current connection accepted", yes(W.Wire.request(obj("{\"version\":1,\"hub\":\"h\",\"generation\":\"7\",\"epoch\":\"e\",\"requestRevision\":1,\"target\":{\"kind\":\"thread\",\"id\":\"a\"}}"), "7", "e")), "yes")
    C.Check.str("numeric generation cannot impersonate string", yes(W.Wire.request(obj("{\"version\":1,\"hub\":\"h\",\"generation\":7,\"epoch\":\"e\",\"requestRevision\":1,\"target\":{\"kind\":\"thread\",\"id\":\"a\"}}"), "7", "e")), "no")
    C.Check.str("unsafe revision refuses before Nat construction", found(W.Wire.nat(obj("{\"n\":9007199254740991}"), "n", 4294967295n)), "invalid")
    C.Check.str("counter boundary accepted", found(W.Wire.nat(obj("{\"n\":4294967295}"), "n", 4294967295n)), "4294967295")
    C.Check.str("counter overflow rejected", found(W.Wire.nat(obj("{\"n\":4294967296}"), "n", 4294967295n)), "invalid")
    C.Check.str("ordinary request cannot consume control namespace", yes(W.Wire.control.id(Some{123n})), "no")
    C.Check.str("top control namespace accepted", yes(W.Wire.control.id(Some{Nat.add(Nat.mul(65536n, 2147483648n), 1n)})), "yes")
    C.Check.str("control namespace never ordinary action rid", yes(W.Wire.ordinary.rid(Some{Nat.mul(65536n, 2147483648n)})), "no")
    +cursor : String = W.Cursor.write("e", target(), "alpha", 39n)
    C.Check.str("cursor roundtrip exact scope", found(W.Cursor.read(cursor, "e", target(), "alpha")), "39")
    C.Check.str("cursor refuses foreign epoch", found(W.Cursor.read(cursor, "old", target(), "alpha")), "invalid")
    C.Check.str("cursor refuses foreign query", found(W.Cursor.read(cursor, "e", target(), "beta")), "invalid")
    C.Check.str("cursor refuses foreign target", found(W.Cursor.read(cursor, "e", obj("{\"kind\":\"thread\",\"id\":\"b\"}"), "alpha")), "invalid")
    +blocks : T.Blocks = T.Blocks.of(String.repeat("😀", 129n))
    C.Check.str("emoji blocks never split surrogate or UTF8 scalar", Nat.show(T.Blocks.n(blocks)), "2")
    C.Check.str("first chunk UTF8 cap exact", yes(W.Wire.within(T.Blocks.get(blocks, 0n), 512n)), "yes")
    C.Check.str("chunk continuation retains final scalar", T.Blocks.get(blocks, 1n), "😀")
    C.Check.str("joining explicit bounded chunks reconstructs exact body", T.Blocks.join(2n, blocks, 0n, Nil{}), String.repeat("😀", 129n))
