import Base
import ./check.bend as C
import ../src/core/signal.bend as G
import ../src/server/thin-signal-text.bend as X

def yes(b: Bool) -> String:
  Bool.pick(String, b, "yes", "no")

def value(r: Map<&2, String> & String) -> String:
  (_, v) = r
  v

def read(m: Map<&2, String>, k: String) -> String:
  value(Map.get(String, "", m, k))

def signals() -> Map<&2, Nat>:
  Map.set(&2, Nat, Map.set(&2, Nat, Map.new(&2, Nat), "working", 1n), "ask", 3n)

def cached(on: Bool) -> X.SignalTextCache:
  X.SignalTextCache.build("epoch", 7n, on, signals())

def merged(on: Bool, current: Map<&2, String>) -> Map<&2, String>:
  G.Signal.cache.overlay(X.SignalTextCache.values(cached(on)), current)

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("online canonical active text", read(merged(True{}, Map.new(&2, String)), "@signal:working"), "1")
    C.Check.str("offline canonical active hidden", read(merged(False{}, Map.new(&2, String)), "@signal:working"), "0")
    C.Check.str("offline blocked status retained", read(merged(False{}, Map.new(&2, String)), "@signal:ask"), "2")
    C.Check.str("current known reserved cannot override canonical", read(merged(True{}, MLeaf{"@signal:working", "999"}), "@signal:working"), "1")
    C.Check.str("current online flag cannot override canonical", read(merged(False{}, MLeaf{"@signal.online", "1"}), "@signal.online"), "0")
    C.Check.str("unknown reserved info remains available", read(merged(True{}, MLeaf{"@signal:ghost", "3"}), "@signal:ghost"), "3")
    C.Check.str("fresh unrelated info remains available", read(merged(True{}, MLeaf{"status", "updated"}), "status"), "updated")
    C.Check.str("fresh provider model content remains available", read(merged(True{}, MLeaf{"models", "changed catalog"}), "models"), "changed catalog")
    C.Check.str("fresh empty unrelated info remains empty", read(merged(True{}, MLeaf{"status", ""}), "status"), "")
    C.Check.str("same dependency and visibility hit", yes(X.SignalTextCache.hit(cached(True{}), "epoch", 7n, True{})), "yes")
    C.Check.str("offline change invalidates", yes(X.SignalTextCache.hit(cached(True{}), "epoch", 7n, False{})), "no")
    C.Check.str("dependency change invalidates", yes(X.SignalTextCache.hit(cached(True{}), "epoch", 8n, True{})), "no")
    C.Check.str("epoch change invalidates", yes(X.SignalTextCache.hit(cached(True{}), "new-epoch", 7n, True{})), "no")
    C.Check.str("oversize is never reusable", yes(X.SignalTextCache.hit(X.SignalTextCache{"epoch", 7n, True{}, Map.new(&2, String), False{}}, "epoch", 7n, True{})), "no")
    C.Check.str("original canonical map is unchanged by overlay", read(X.SignalTextCache.values(cached(True{})), "status"), "")
