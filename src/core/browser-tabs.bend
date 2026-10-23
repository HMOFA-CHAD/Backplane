import Base
import ./json.bend as J

# Public Browser chrome only, retained in memory for canonical thin views
# and renderer reconnects. No grant, recorder, document or profile metadata.
def Tabs.row(+row: J.Json, index: Nat) -> J.Json:
  J.Json.obj([J.KV{"id", J.Str{J.Json.get_str(row, "id", "")}}, J.KV{"index", J.Num{Nat.show(index)}},
    J.KV{"url", J.Str{J.Json.get_str(row, "url", "")}}, J.KV{"title", J.Str{J.Json.get_str(row, "title", "")}}, J.KV{"active", J.Flag{J.Json.get_bool(row, "active", False{})}}])

def Tabs.rows(rows: List<&2, J.Json>, +index: Nat) -> List<&2, J.Json>:
  match rows:
    case Nil{}: Nil{}
    case row <> rest: Tabs.row(row, index) <> Tabs.rows(rest, Nat.add(index, 1n))

def Tabs.event(+event: J.Json) -> J.Json:
  J.Json.obj([J.KV{"event", J.Str{"tabs"}}, J.KV{"page", J.Str{J.Json.get_str(event, "page", "")}},
    J.KV{"url", J.Str{J.Json.get_str(event, "url", "")}}, J.KV{"tabs", J.Json.arr(Tabs.rows(J.Json.elems(J.Json.get_obj(event, "tabs")), 0n))}])

def Tabs.key(+owner: String) -> String:
  "browser.tabs." ++ owner

def Tabs.value(fields: List<&2, J.KV>, owner: String) -> String:
  J.Json.get_str(J.Json.obj(fields), Tabs.key(owner), "")

def Tabs.keep(same: Bool, name: String, value: J.Json, rest: List<&2, J.KV>) -> List<&2, J.KV>:
  match same:
    case True{}: rest
    case False{}: J.KV{name, value} <> rest

def Tabs.without(fields: List<&2, J.KV>, +key: String) -> List<&2, J.KV>:
  match fields:
    case Nil{}: Nil{}
    case J.KV{+name, value} <> rest:
      Tabs.keep(String.eq(name, key), name, value, Tabs.without(rest, key))

def Tabs.changed(+fields: List<&2, J.KV>, +event: J.Json) -> Bool:
  Bool.not(String.eq(Tabs.value(fields, J.Json.get_str(event, "page", "")), J.Json.show(Tabs.event(event))))

# Same bound as the existing browser page catalogue; replace one owner's
# complete inventory, including its empty inventory after the final close.
def Tabs.cache(+fields: List<&2, J.KV>, +event: J.Json) -> List<&2, J.KV>:
  +key = Tabs.key(J.Json.get_str(event, "page", ""))
  List.take(&2, J.KV, J.KV{key, J.Str{J.Json.show(Tabs.event(event))}} <> Tabs.without(fields, key), 64n)
