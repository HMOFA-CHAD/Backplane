import Base
import ../src/core/model.bend as M
import ../src/core/json.bend as J
import ../src/core/thin.bend as T
import ../src/server/thin-view.bend as V

def obj(text: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{})

def state() -> M.State:
  M.State.replay([M.ThreadCreated{"t", "", "Public thread", M.Local{}, "", "", "codex", "", 1n},
    M.MessagePosted{"t", "m", M.Assistant{}, "needle " ++ String.repeat("x", 900n) ++ "日本語🙂", 2n}], M.State.empty())

def request() -> J.Json:
  obj("{\"hub\":\"h\",\"cid\":\"fixture\",\"target\":{\"kind\":\"thread\",\"id\":\"t\"},\"nativeRenderer\":\"ios-v1\",\"session\":{\"sel\":\"t\",\"rid\":100,\"drafts\":{},\"open\":{},\"info\":{},\"outbox\":{},\"adding\":false,\"panel\":false}}")

def main() -> IO(Unit):
  do IO<Unit>:
    +st : M.State = state()
    +index : T.Index = T.Index.of(st)
    +p : J.Json = request()
    +rows : List<&2, String> = T.Index.page(index, "t", 0n, 32n)
    +shown : J.Json = V.Render.view(False{}, st, index, obj("{}"), obj("{}"), 3n, p, "origin", rows)
    +message : J.Json = V.Message.result(T.Index.row(index, 1n), 0n, V.Obj.put(p, "entryId", J.Str{"m"}), "origin")
    +search : J.Json = V.Search.render(index, st, V.Obj.put(p, "query", J.Str{"needle"}), "origin", 0n)
    IO.print(J.Json.show(J.Json.obj([J.KV{"fixture", J.Str{"thin-production-wire"}}, J.KV{"target", J.Json.get_obj(p, "target")}, J.KV{"open", shown}, J.KV{"message", J.Json.get_obj(message, "message")}, J.KV{"search", J.Json.get_obj(search, "search")}])))
