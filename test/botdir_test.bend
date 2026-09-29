import Base
import ./check.bend as C
import ../src/core/bothub.bend as D
import ../src/core/bot.bend as B
import ../src/core/json.bend as J
import ../src/server/botnet.bend as BN

def rows() -> List<&2, J.Json>:
  [D.Dir.item("a", "alpha", 7n, "miso", "work", 42n), D.Dir.item("b", "beta", 3n, "nori", "ready", 40n)]

def summary(xs: List<&2, J.Json>) -> String:
  match xs:
    case Nil{}:
      ""
    case +o <> t:
      D.Dir.key(o) ++ ":" ++ J.Json.get_str(o, "state", "") ++ ":" ++ J.Json.as_raw(J.Json.get(o, "seen"), "") ++ ";" ++ summary(t)

def work(w: D.DirWork) -> String:
  match w:
    case D.DirWork{a, q}:
      String.join(a, ",") ++ "|" ++ String.join(q, ",")

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("failure changes only its peer and preserves seen", summary(D.Dir.merge(None{}, rows(), "a")), "a:miso:away:42;b:nori:ready:40;")
    C.Check.str("success replaces all old rows for one peer", summary(D.Dir.merge(Some{[D.Dir.item("a", "alpha", 1n, "new", "ready", 50n)]}, rows(), "a")), "a:new:ready:50;b:nori:ready:40;")
    C.Check.str("empty success removes only that peer", summary(D.Dir.merge(Some{Nil{}}, rows(), "a")), "b:nori:ready:40;")
    C.Check.str("late result after URL change is ignored", summary(D.Dir.accept(False{}, Some{Nil{}}, rows(), "a")), summary(rows()))
    C.Check.str("cache rows are away, ordered, and unlinked peers dropped", summary(D.Dir.cached(rows(), [B.Peer{"a", "alpha", "http://a", 0n, False{}}])), "a:miso:away:42;")
    C.Check.str("cache peer IDs never match another peer name", summary(D.Dir.cached(rows(), [B.Peer{"c", "a", "http://c", 0n, False{}}])), "")
    C.Check.str("bot order independent of arrival", summary(D.Dir.merge(Some{[D.Dir.item("a", "alpha", 0n, "z", "ready", 5n), D.Dir.item("a", "alpha", 0n, "a", "ready", 5n)]}, rows(), "a")), "a:a:ready:5;a:z:ready:5;b:nori:ready:40;")
    C.Check.str("valid object is a failed directory", J.Json.show(J.Json.bool(Maybe.is_none(&2, List<&2, J.Json>, BN.Bn.fetched(BN.Resp{200n, "{}"}, "a", "alpha", 50n)))), "true")
    C.Check.str("malformed JSON is a failed directory", J.Json.show(J.Json.bool(Maybe.is_none(&2, List<&2, J.Json>, BN.Bn.fetched(BN.Resp{200n, "["}, "a", "alpha", 50n)))), "true")
    C.Check.str("HTTP failure is a failed directory", J.Json.show(J.Json.bool(Maybe.is_none(&2, List<&2, J.Json>, BN.Bn.fetched(BN.Resp{401n, "[]"}, "a", "alpha", 50n)))), "true")
    C.Check.str("directory timeout is separate from delivery", String.join(BN.Bn.dir.args("http://a"), " "), "-sS --proto =http,https --connect-timeout 2 -m 4 --max-filesize 1048576 -X GET -H @- -w \n%{http_code} --url http://a")
    C.Check.str("delivery retains its timeout", J.Json.show(J.Json.bool(List.contains(~String, ~String.eq, BN.Bn.args(True{}, "file", "http://a"), "15"))), "true")
    C.Check.str("active peer cannot be queued twice", work(D.DirWork.add(D.DirWork{["a"], ["b"]}, "a")), "a|b")
    C.Check.str("pending peer cannot be queued twice", work(D.DirWork.add(D.DirWork{["a"], ["b"]}, "b")), "a|b")
    C.Check.str("four requests at most", work(D.DirPlan.work(D.DirWork.plan(D.DirWork{[], ["a", "b", "c", "d", "e"]}))), "d,c,b,a|e")
    C.Check.str("completion fills slot without waiting for others", String.join(D.DirPlan.launch(D.DirWork.plan(D.DirWork.finish(D.DirWork{["d", "c", "b", "a"], ["e"]}, "b"))), ","), "e")
    C.Check.str("empty directories cannot trigger a request loop", J.Json.show(J.Json.bool(D.Dir.stale(Nil{}, "a"))), "false")
    C.Check.str("a discovered returning peer refreshes at once", Nat.show(List.length(&2, B.Peer, D.Dir.returned([B.Peer{"a", "alpha", "http://a", 0n, False{}}], Nil{}, [J.Json.obj([J.KV{"url", J.Str{"http://a"}}])]))), "1")
