import Base
import ./check.bend as C
import ../src/server/thin-view.bend as V
import ../src/core/thin.bend as T
import ../src/core/thin-wire.bend as W
import ../src/core/model.bend as M
import ../src/core/json.bend as J

def target() -> J.Json:
  V.Target.json("thread", "a")

def index() -> T.Index:
  T.Index.post(T.Index.post(T.Index.empty(), M.Msg{"long", "a", M.Assistant{}, String.repeat("😀", 129n), 1n}), M.Msg{"other", "b", M.Assistant{}, "other private body", 2n})

def request(+id: String, cursor: String) -> J.Json:
  J.Json.obj([J.KV{"target", target()}, J.KV{"entryId", J.Str{id}}, J.KV{"cursor", J.Str{cursor}}])

def cursor() -> String:
  W.Cursor.write("epoch", target(), "message:1", 1n)

def code(r: V.MessageRead) -> String:
  match r:
    case V.MessageRead{code, _, _}: code

def offset(r: V.MessageRead) -> Nat:
  match r:
    case V.MessageRead{_, _, n}: n

def version(r: V.MessageRead) -> Nat:
  match r:
    case V.MessageRead{_, row, _}: T.Row.n(row)

def read(+p: J.Json) -> V.MessageRead:
  V.Message.read(index(), "a", p, "epoch", ["1"], M.State.empty())

def check(name: String, b: Bool) -> IO(Unit):
  C.Check.str(name, Bool.pick(String, b, "yes", "no"), "yes")

# Build the boundary payload without String.repeat's stack frame per byte.
def boundary_text(n: Nat, acc: String) -> String:
  match n:
    case 0n: acc
    case 1n+p: boundary_text(p, SCon{'x', acc})

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("visible exact entry may request first chunk", code(read(request("long", ""))), "")
    C.Check.str("first explicit chunk starts at zero", Nat.show(offset(read(request("long", "")))), "0")
    C.Check.str("explicit cursor retains immutable version", Nat.show(version(read(request("long", cursor())))), "1")
    C.Check.str("cursor starts after visible scalar-safe block", Nat.show(offset(read(request("long", cursor())))), "1")
    C.Check.str("known continuation accepted", code(read(request("long", cursor()))), "")
    C.Check.str("unseen initial id does not scan history", code(V.Message.read(index(), "a", request("long", ""), "epoch", Nil{}, M.State.empty())), "NOT_FOUND")
    C.Check.str("foreign body refused despite valid indexed ordinal", code(read(request("other", W.Cursor.write("epoch", target(), "message:2", 1n)))), "STALE_CURSOR")
    C.Check.str("entry id cannot change under original cursor", code(read(request("other", cursor()))), "STALE_CURSOR")
    C.Check.str("another target cannot borrow cursor", code(read(V.Obj.put(request("long", cursor()), "target", V.Target.json("thread", "b")))), "STALE_CURSOR")
    C.Check.str("old epoch refuses continuation", code(read(request("long", W.Cursor.write("old", target(), "message:1", 1n)))), "STALE_CURSOR")
    C.Check.str("zero cursor offset cannot repeat prefix", code(read(request("long", W.Cursor.write("epoch", target(), "message:1", 0n)))), "STALE_CURSOR")
    C.Check.str("completed offset cannot continue", code(read(request("long", W.Cursor.write("epoch", target(), "message:1", 2n)))), "STALE_CURSOR")
    C.Check.str("unknown ordinal refused", code(read(request("long", W.Cursor.write("epoch", target(), "message:999", 1n)))), "STALE_CURSOR")
    C.Check.str("noncanonical ordinal refused", code(read(request("long", W.Cursor.write("epoch", target(), "message:01", 1n)))), "STALE_CURSOR")
    C.Check.str("different cursor purpose refused", code(read(request("long", W.Cursor.write("epoch", target(), "search", 1n)))), "STALE_CURSOR")
    C.Check.str("malformed cursor refused", code(read(request("long", "broken"))), "STALE_CURSOR")
    C.Check.str("overlong cursor bounded before parsing", code(read(request("long", String.repeat("x", 1025n)))), "LIMIT")
    C.Check.str("missing initial entry refused", code(read(request("absent", ""))), "NOT_FOUND")
    C.Check.str("foreign initial entry refused", code(V.Message.read(index(), "a", request("other", ""), "epoch", ["2"], M.State.empty())), "NOT_FOUND")
    C.Check.str("continuation keeps last exact Unicode scalar", J.Json.get_str(J.Json.get_obj(V.Message.result(T.Index.row(index(), 1n), 1n, request("long", cursor()), "epoch"), "message"), "text", ""), "😀")
    C.Check.str("empty window cannot wrap to latest page", Bool.pick(String, J.Json.get_bool(V.Page.window(index(), "a", request("long", ""), "epoch", Nil{}), "hasMore", True{}), "yes", "no"), "no")
    C.Check.str("empty window has no older cursor", J.Json.get_str(V.Page.window(index(), "a", request("long", ""), "epoch", Nil{}), "older", "invalid"), "")
    C.Check.str("invalidations expose exact owning view only", J.Json.get_str(W.Wire.changed("7", "epoch", 99n, "v1", target()), "viewId", ""), "v1")
    C.Check.str("invalidation revision remains decimal text", J.Json.get_str(W.Wire.changed("7", "epoch", 99n, "v1", target()), "viewRevision", ""), "99")
    C.Check.str("invalidation has no message text field", J.Json.get_str(W.Wire.changed("7", "epoch", 99n, "v1", target()), "text", "absent"), "absent")
    C.Check.str("invalidation has no canonical applied cursor", J.Json.get_str(W.Wire.changed("7", "epoch", 99n, "v1", target()), "since", "absent"), "absent")
    check("single term query valid", V.Query.valid("exact"))
    check("uppercase normalization valid", V.Query.valid("EXACT"))
    check("eight tokens valid", V.Query.valid("a b c d e f g h"))
    check("nine tokens refused", Bool.not(V.Query.valid("a b c d e f g h i")))
    check("64 codepoint token valid", V.Query.valid(String.repeat("a", 64n)))
    check("65 codepoint token refused", Bool.not(V.Query.valid(String.repeat("a", 65n))))
    check("long token never silently disappears from conjunction", Bool.not(V.Query.valid("exact " ++ String.repeat("a", 65n))))
    check("Japanese query valid", V.Query.valid("日本語"))
    check("supplementary scalar boundary valid", V.Query.valid(String.repeat("😀", 64n)))
    check("UTF8 query bytes overflow refused", Bool.not(V.Query.valid(String.repeat("😀", 65n))))
    check("empty query refused", Bool.not(V.Query.valid("")))
    check("delimiters only query refused", Bool.not(V.Query.valid("--- , .")))
    check("ordinary invalidation fits tiny budget", W.Wire.within(J.Json.show(W.Wire.changed("7", "epoch", 99n, "v1", target())), 1024n))
    check("oversized invalidation target fails budget", Bool.not(W.Wire.within(J.Json.show(W.Wire.changed("7", "epoch", 99n, "v1", V.Target.json("thread", String.repeat("x", 1024n)))), 1024n)))
    check("normal request maximum allowed", W.Wire.within(boundary_text(262144n, ""), 262144n))
    check("one byte beyond request maximum refused", Bool.not(W.Wire.within(boundary_text(262145n, ""), 262144n)))
