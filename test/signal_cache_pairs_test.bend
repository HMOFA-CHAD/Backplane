import Base
import ./check.bend as C
import ../src/core/signal.bend as SG
import ../src/core/json.bend as J

def values(xs: List<&2, Sigma<&2, &2, String, _ => String>>) -> List<&2, J.KV>:
  match xs:
    case Nil{}: Nil{}
    case (k, v) <> rest: J.KV{k, J.Str{v}} <> values(rest)

def text(m: Map<&2, String>) -> String:
  J.Json.show(J.Json.obj(values(Map.to_list(&2, String, m))))

def exact(+online: Bool, +signals: Map<&2, Nat>, +info: Map<&2, String>) -> String:
  Bool.pick(String, C.Check.same(text(SG.Signal.cache(online, signals, info)), text(SG.Signal.cache.go(Map.keys(&2, Nat, signals), online, signals, Map.set(&2, String, info, "@signal.online", Bool.pick(String, online, "1", "0"))))), "yes", "no")

def single(n: Nat) -> Map<&2, Nat>:
  Map.set(&2, Nat, Map.new(&2, Nat), "t", n)

def info() -> Map<&2, String>:
  Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.new(&2, String), "models", "fresh model metadata"), "draft", "日本語 IME"), "@signal:ghost", "3")

def many(+n: Nat, acc: Map<&2, Nat>) -> Map<&2, Nat>:
  match n:
    case 0n: acc
    case 1n+k: many(k, Map.set(&2, Nat, acc, "thread-" ++ Nat.show(k), Nat.mod(k, 5n)))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("empty online map exact", exact(True{}, Map.new(&2, Nat), info()), "yes")
    C.Check.str("empty offline map exact", exact(False{}, Map.new(&2, Nat), info()), "yes")
    C.Check.str("inactive online exact", exact(True{}, single(0n), info()), "yes")
    C.Check.str("active online exact", exact(True{}, single(1n), info()), "yes")
    C.Check.str("blocked online exact", exact(True{}, single(2n), info()), "yes")
    C.Check.str("blocked working online exact", exact(True{}, single(3n), info()), "yes")
    C.Check.str("settled online exact", exact(True{}, single(4n), info()), "yes")
    C.Check.str("active offline exact", exact(False{}, single(1n), info()), "yes")
    C.Check.str("blocked working offline exact", exact(False{}, single(3n), info()), "yes")
    C.Check.str("settled offline exact", exact(False{}, single(4n), info()), "yes")
    C.Check.str("Unicode and reserved existing keys exact", exact(True{}, Map.set(&2, Nat, single(1n), "日本語:@signal:child", 3n), Map.set(&2, String, info(), "@signal:t", "stale")), "yes")
    C.Check.str("existing online sentinel overwritten exactly", exact(False{}, single(2n), Map.set(&2, String, info(), "@signal.online", "stale")), "yes")
    C.Check.str("64 mixed signals online exact", exact(True{}, many(64n, Map.new(&2, Nat)), info()), "yes")
    C.Check.str("64 mixed signals offline exact", exact(False{}, many(64n, Map.new(&2, Nat)), info()), "yes")
