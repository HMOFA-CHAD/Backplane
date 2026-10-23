import Base
import ../../src/core/telemetry.bend as T
import ../check.bend as C

def check(name: String, ok: Bool) -> IO(Unit):
  C.Check.str(name, Bool.pick(String, ok, "yes", "no"), "yes")

def key() -> String:
  "0000000000000000000000000000000000000000000000000000000000000000"

def main() -> IO(Unit):
  do IO<Unit>:
    check("production HTTPS configured tuple evaluates without native overflow", T.Tm.config.ok("", "https://backplaneworks.com/api/v1/events", "rel-fixture", key(), "release"))
    check("production HTTPS never classifies as loopback", Bool.not(T.Tm.loopback("https://backplaneworks.com/api/v1/events")))
    check("legacy receiver endpoint refused", Bool.not(T.Tm.config.ok("", "https://backplane.works/api/v1/events", "rel-fixture", key(), "release")))
    check("another HTTPS endpoint still refused", Bool.not(T.Tm.config.ok("", "https://example.invalid/api/v1/events", "rel-fixture", key(), "release")))
    check("valid loopback test tuple preserved", T.Tm.config.ok("1", "http://127.0.0.1:4567/api/v1/events", "dev-fixture", key(), "dev"))
    check("production cannot use loopback endpoint", Bool.not(T.Tm.config.ok("", "http://127.0.0.1:4567/api/v1/events", "rel-fixture", key(), "release")))
    check("port lower boundary", T.Tm.loopback("http://127.0.0.1:1/api/v1/events"))
    check("port upper boundary", T.Tm.loopback("http://127.0.0.1:65535/api/v1/events"))
    check("zero port refused", Bool.not(T.Tm.loopback("http://127.0.0.1:0/api/v1/events")))
    check("oversized port refused", Bool.not(T.Tm.loopback("http://127.0.0.1:65536/api/v1/events")))
    check("negative port refused", Bool.not(T.Tm.loopback("http://127.0.0.1:-1/api/v1/events")))
    check("nondigit port refused", Bool.not(T.Tm.loopback("http://127.0.0.1:.works/api/v1/events")))
    check("Unicode port refused", Bool.not(T.Tm.loopback("http://127.0.0.1:日本語/api/v1/events")))
    check("very long digit port refused", Bool.not(T.Tm.loopback("http://127.0.0.1:999999999999999999999999999999/api/v1/events")))
    check("foreign host refused", Bool.not(T.Tm.loopback("http://127.0.0.2:4567/api/v1/events")))
    check("wrong path refused", Bool.not(T.Tm.loopback("http://127.0.0.1:4567/api/v1/events/extra")))
    C.Check.str("invalid decimal returns zero without unsafe subtraction", Nat.show(T.Tm.num(".works")), "0")
    C.Check.str("empty decimal stays zero", Nat.show(T.Tm.num("")), "0")
    C.Check.str("valid epoch seconds preserved", Nat.show(T.Tm.num("1792592831")), "1792592831")
    C.Check.str("valid retry interval preserved", Nat.show(T.Tm.num("7200")), "7200")
    C.Check.str("native maximum accepted", Nat.show(T.Tm.num("281474976710655")), "281474976710655")
    C.Check.str("native maximum plus one refused", Nat.show(T.Tm.num("281474976710656")), "0")
    C.Check.str("JS safe integer above native limit refused", Nat.show(T.Tm.num("9007199254740991")), "0")
    C.Check.str("long leading zero representation preserved", Nat.show(T.Tm.num("0000000000000000000000000001")), "1")
    check("missing key still refused", Bool.not(T.Tm.config.ok("", "https://backplaneworks.com/api/v1/events", "rel-fixture", "", "release")))
    C.Check.str("fourteen digit upper range preserved", Nat.show(T.Tm.num("99999999999999")), "99999999999999")
    C.Check.str("fifteen digit lower range preserved", Nat.show(T.Tm.num("100000000000000")), "100000000000000")
    C.Check.str("lexically below native maximum preserved", Nat.show(T.Tm.num("281474976710654")), "281474976710654")
    C.Check.str("fifteen digit high range refused", Nat.show(T.Tm.num("999999999999999")), "0")
    C.Check.str("sixteen significant digits refused", Nat.show(T.Tm.num("1000000000000000")), "0")
    C.Check.str("leading zero native maximum preserved", Nat.show(T.Tm.num("0000281474976710655")), "281474976710655")
    C.Check.str("leading zero oversized decimal refused", Nat.show(T.Tm.num("0000281474976710656")), "0")
    C.Check.str("leading zeros never admit nondigits", Nat.show(T.Tm.num("000000.works")), "0")
