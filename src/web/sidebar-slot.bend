import Base
import ../core/json.bend as J
import ./dom.bend as D

# Private server render plumbing. A slot is replaced before the normal full
# presentation is sent; no renderer cache key, reference, or authority is sent.
def Slot.placeholder() -> D.Node:
  D.El{"bp-server-sidebar-slot", "sidebar", Nil{}, Nil{}}

def Slot.set.fields(fs: J.Json, +key: String, +value: J.Json) -> J.Json:
  match fs:
    case J.Field{+k, v, rest}:
      J.Field{k, Bool.pick(J.Json, String.eq(k, key), value, v), Slot.set.fields(rest, key, value)}
    case _: fs

def Slot.set(o: J.Json, key: String, value: J.Json) -> J.Json:
  match o:
    case J.Obj{fs}: J.Obj{Slot.set.fields(fs, key, value)}
    case _: o

def Slot.is(+o: J.Json, +tag: String) -> Bool:
  Bool.and(String.eq(J.Json.get_str(o, "type", ""), "element"),
    Bool.and(String.eq(J.Json.get_str(o, "tag", ""), tag), String.eq(J.Json.get_str(o, "key", ""), "sidebar")))

# Match the original Json constructors so each recursive call is structurally
# smaller. A matched region is returned whole without traversing its children.
def Slot.find.go(o: J.Json, +tag: String, hit: Bool) -> List<&2, J.Json>:
  match o hit:
    case J.Obj{fs} True{}: [J.Obj{fs}]
    case J.Obj{fs} False{}: Slot.find.go(fs, tag, False{})
    case J.Field{_, +v, tail} _:
      List.append(&2, J.Json, Slot.find.go(v, tag, Slot.is(v, tag)), Slot.find.go(tail, tag, False{}))
    case J.Arr{items} _: Slot.find.go(items, tag, False{})
    case J.Item{+head, tail} _:
      List.append(&2, J.Json, Slot.find.go(head, tag, Slot.is(head, tag)), Slot.find.go(tail, tag, False{}))
    case _ _: Nil{}

def Slot.one(xs: List<&2, J.Json>) -> J.Json:
  match xs:
    case o <> Nil{}: o
    case _: J.Null{}

def Slot.sidebar(+o: J.Json) -> J.Json:
  Slot.one(Slot.find.go(o, "aside", Slot.is(o, "aside")))

def Slot.count(+o: J.Json) -> Nat:
  List.length(&2, J.Json, Slot.find.go(o, "bp-server-sidebar-slot", Slot.is(o, "bp-server-sidebar-slot")))

def Slot.replace.go(o: J.Json, +sidebar: J.Json, hit: Bool) -> J.Json:
  match o hit:
    case J.Obj{_} True{}: sidebar
    case J.Obj{fs} False{}: J.Obj{Slot.replace.go(fs, sidebar, False{})}
    case J.Field{k, +v, tail} _:
      J.Field{k, Slot.replace.go(v, sidebar, Slot.is(v, "bp-server-sidebar-slot")), Slot.replace.go(tail, sidebar, False{})}
    case J.Arr{items} _: J.Arr{Slot.replace.go(items, sidebar, False{})}
    case J.Item{+head, tail} _:
      J.Item{Slot.replace.go(head, sidebar, Slot.is(head, "bp-server-sidebar-slot")), Slot.replace.go(tail, sidebar, False{})}
    case _ _: o

def Slot.replace(+o: J.Json, sidebar: J.Json) -> J.Json:
  Slot.replace.go(o, sidebar, Slot.is(o, "bp-server-sidebar-slot"))
