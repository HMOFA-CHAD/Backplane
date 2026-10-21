import Base
import ../src/web/dom.bend as D

# Reading emitted web nodes the way test/tools/web_mail_room_*.mjs read them,
# so the Bend tests check the same things the JS drivers check.

# every node of a tree list in pre-order, reversed onto acc
def Wn.all.go(xs: List<&2, D.Node>, acc: List<&2, D.Node>) -> List<&2, D.Node>:
  match xs:
    case Nil{}:
      acc
    case D.El{tag, key, attrs, +kids} <> t:
      Wn.all.go(t, Wn.all.go(kids, D.El{tag, key, attrs, kids} <> acc))
    case D.Txt{s} <> t:
      Wn.all.go(t, D.Txt{s} <> acc)

def Wn.all(n: D.Node) -> List<&2, D.Node>:
  List.reverse(&2, D.Node, Wn.all.go([n], Nil{}))

def Wn.key(n: D.Node) -> String:
  match n:
    case D.El{_, key, _, _}: key
    case D.Txt{_}: ""

def Wn.attrs(n: D.Node) -> List<&2, D.Attr>:
  match n:
    case D.El{_, _, attrs, _}: attrs
    case D.Txt{_}: Nil{}

# the value of the first attribute named `name`, "" when there is none
def Wn.attr.go(xs: List<&2, D.Attr>, +name: String) -> String:
  match xs:
    case Nil{}: ""
    case D.At{+n, v} <> t: Bool.pick(String, String.eq(n, name), v, Wn.attr.go(t, name))
    case D.On{_, _} <> t: Wn.attr.go(t, name)

def Wn.attr(n: D.Node, +name: String) -> String:
  Wn.attr.go(Wn.attrs(n), name)

# the action of the first handler for `event`, "" when there is none
def Wn.on.go(xs: List<&2, D.Attr>, +event: String) -> String:
  match xs:
    case Nil{}: ""
    case D.At{_, _} <> t: Wn.on.go(t, event)
    case D.On{+e, a} <> t: Bool.pick(String, String.eq(e, event), a, Wn.on.go(t, event))

def Wn.on(n: D.Node, +event: String) -> String:
  Wn.on.go(Wn.attrs(n), event)

# "name=value" for each attribute named a or b, in attribute order
def Wn.pick.go(xs: List<&2, D.Attr>, +a: String, +b: String, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case D.At{+n, +v} <> t:
      Wn.pick.go(t, a, b, Bool.pick(List<&2, String>, Bool.or(String.eq(n, a), String.eq(n, b)), (n ++ "=" ++ v) <> acc, acc))
    case D.On{_, _} <> t: Wn.pick.go(t, a, b, acc)

def Wn.pick(n: D.Node, +a: String, +b: String) -> String:
  String.join(Wn.pick.go(Wn.attrs(n), a, b, Nil{}), ",")

# all text under the given nodes, in order, reversed onto acc
def Wn.text.go(xs: List<&2, D.Node>, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case D.Txt{s} <> t: Wn.text.go(t, String.reverse.go(s, acc))
    case D.El{_, _, _, kids} <> t: Wn.text.go(t, Wn.text.go(kids, acc))

def Wn.text(n: D.Node) -> String:
  String.reverse(Wn.text.go([n], ""))

# the text of a node's first child when that child is text (JS kids.head.text)
def Wn.head.go(xs: List<&2, D.Node>) -> String:
  match xs:
    case D.Txt{s} <> _: s
    case _: "<no text>"

def Wn.head(n: D.Node) -> String:
  match n:
    case D.El{_, _, _, kids}: Wn.head.go(kids)
    case D.Txt{_}: "<no text>"

# the first node keyed `key`
def Wn.find.go(xs: List<&2, D.Node>, +key: String) -> Maybe<&2, D.Node>:
  match xs:
    case Nil{}: None{}
    case +h <> t: Bool.pick(Maybe<&2, D.Node>, String.eq(Wn.key(h), key), Some{h}, Wn.find.go(t, key))

def Wn.found.head(m: Maybe<&2, D.Node>) -> String:
  match m:
    case None{}: "<missing>"
    case Some{n}: Wn.head(n)

def Wn.found.text(m: Maybe<&2, D.Node>) -> String:
  match m:
    case None{}: ""
    case Some{n}: Wn.text(n)

def Wn.found.attr(m: Maybe<&2, D.Node>, +name: String) -> String:
  match m:
    case None{}: "<missing>"
    case Some{n}: Wn.attr(n, name)

def Wn.found.pick(m: Maybe<&2, D.Node>, +a: String, +b: String) -> String:
  match m:
    case None{}: "<missing>"
    case Some{n}: Wn.pick(n, a, b)

# first text child of the node keyed `key` in the tree (the reader driver's text())
def Wn.key_head(root: D.Node, +key: String) -> String:
  Wn.found.head(Wn.find.go(Wn.all(root), key))

# all text of the node keyed `key`, "" when absent (the transition driver's text())
def Wn.key_text(root: D.Node, +key: String) -> String:
  Wn.found.text(Wn.find.go(Wn.all(root), key))

def Wn.key_attr(root: D.Node, +key: String, +name: String) -> String:
  Wn.found.attr(Wn.find.go(Wn.all(root), key), name)

def Wn.key_pick(root: D.Node, +key: String, +a: String, +b: String) -> String:
  Wn.found.pick(Wn.find.go(Wn.all(root), key), a, b)

# texts of nodes whose class is exactly `cls`, sorted, joined by "|"
def Wn.class.go(xs: List<&2, D.Node>, +cls: String, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case +h <> t:
      Wn.class.go(t, cls, Bool.pick(List<&2, String>, String.eq(Wn.attr(h, "class"), cls), Wn.text(h) <> acc, acc))

def Wn.class_texts(root: D.Node, +cls: String) -> String:
  String.join(List.sort(~String, ~String.is_le, Wn.class.go(Wn.all(root), cls, Nil{})), "|")

# data-value of nodes whose click sends `action`, sorted, joined by "|"
def Wn.act.go(xs: List<&2, D.Node>, +action: String, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case +h <> t:
      Wn.act.go(t, action, Bool.pick(List<&2, String>, String.eq(Wn.on(h, "click"), action), Wn.attr(h, "data-value") <> acc, acc))

def Wn.act_values(root: D.Node, +action: String) -> String:
  String.join(List.sort(~String, ~String.is_le, Wn.act.go(Wn.all(root), action, Nil{})), "|")
