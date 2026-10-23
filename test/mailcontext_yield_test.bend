import Base
import ../src/core/json.bend as J
import ../src/core/store.bend as ST
import ../src/server/mailcontext.bend as CX
import ./check.bend as C

def line(+owner: String, +id: String, +text: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"$", J.Str{"MessagePosted"}}, J.KV{"thread", J.Str{owner}},
    J.KV{"msg", J.Str{id}}, J.KV{"role", J.Str{"user"}}, J.KV{"text", J.Str{text}}, J.KV{"at", J.Num{"1"}}]))

def many(+n: Nat) -> List<&2, String>:
  match n:
    case 0n: Nil{}
    case 1n+k: line("owner", Nat.show(n), "Hardware context") <> many(k)

def noise(+n: Nat, tail: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: tail
    case 1n+k: line("other", Nat.show(n), "Unrelated PRIVATE body") <> noise(k, tail)

def compare(+name: String, +ls: List<&2, String>, +args: J.Json) -> IO(Unit):
  do IO<Unit>:
    +actual : J.Json <- CX.Context.read(True{}, "", "owner", args, ls)
    C.Check.str(name, J.Json.show(actual), J.Json.show(CX.Context.result(CX.Context.log.rows(ls, "owner",
      String.to_lower(String.take(J.Json.get_str(args, "query", ""), 200n)), J.Json.get_nat(args, "before", 0n), ST.Store.size(ls), 21n, Nil{}), "owner")))

def step_check(scan: CX.LogScan) -> IO(Unit):
  match scan:
    case CX.LogScan{lines, seq, remaining, rows}:
      do IO<Unit>:
        C.Check.str("one quantum keeps unscanned history", Nat.show(ST.Store.size(lines)), "65")
        C.Check.str("one quantum preserves global wire position", Nat.show(seq), "65")
        C.Check.str("unrelated records do not consume lookahead", Nat.show(remaining), "21")
        C.Check.str("unrelated records never become owner rows", Nat.show(List.length(&2, List<&2, String>, rows)), "0")

def main() -> IO(Unit):
  do IO<Unit>:
    compare("empty history", Nil{}, J.Json.obj(Nil{}))
    compare("sparse owner history across batch boundaries", noise(96n, many(3n)), J.Json.obj(Nil{}))
    compare("case-insensitive search after unrelated history", noise(65n, many(3n)), J.Json.obj([J.KV{"query", J.Str{"HARDWARE"}}]))
    compare("no-match search scans every batch", noise(96n, many(3n)), J.Json.obj([J.KV{"query", J.Str{"absent"}}]))
    compare("global cursor counts malformed and other-owner lines", [line("owner", "new", "Hardware new"), "malformed", line("other", "private", "Hardware PRIVATE"), line("owner", "old", "Hardware old")], J.Json.obj([J.KV{"before", J.Num{"3"}}]))
    compare("lookahead stops at twenty plus one", many(40n), J.Json.obj(Nil{}))
    step_check(CX.Context.log.step(CX.Context.log.quantum(), CX.LogScan{noise(96n, many(1n)), 97n, 21n, Nil{}}, "owner", "", 0n))
    +page : J.Json <- CX.Context.read(True{}, "", "owner", J.Json.obj(Nil{}), many(22n))
    C.Check.str("page has twenty whole messages", Nat.show(List.length(&2, J.Json, J.Json.elems(J.Json.get_obj(page, "messages")))), "20")
    C.Check.str("next is last returned global seq", Nat.show(J.Json.get_nat(page, "next", 0n)), "3")
    +tail : J.Json <- CX.Context.read(True{}, "", "owner", J.Json.obj([J.KV{"before", J.Json.get_obj(page, "next")}]), many(22n))
    C.Check.str("next page has no gap or overlap", Nat.show(List.length(&2, J.Json, J.Json.elems(J.Json.get_obj(tail, "messages")))), "2")
    +denied : J.Json <- CX.Context.read(False{}, "", "owner", J.Json.obj(Nil{}), noise(96n, many(1n)))
    C.Check.str("authorization still fails closed", Bool.show(Maybe.is_some(&2, J.Json, J.Json.get(denied, "error"))), "True")
    +scoped : J.Json <- CX.Context.read(True{}, "", "owner", J.Json.obj(Nil{}), noise(96n, many(1n)))
    C.Check.str("unrelated private text never escapes", Bool.show(String.contains(J.Json.show(scoped), "PRIVATE")), "False")
