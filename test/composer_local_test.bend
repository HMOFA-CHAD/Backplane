import Base
import ./check.bend as C
import ../src/core/i18n.bend as I
import ../src/web/view.bend as V
import ../src/web/dom.bend as D

# The composer as typed (view.bend's View.local, run in the browser over the
# hub's last render): while that render is for an older draft (a streaming
# turn keeps the hub busy), the send button and the slash commands follow
# what is typed at once.

def comp(+draft: String, +run: Bool) -> D.Node:
  V.View.composer.loc(I.En{}, draft, Bool.pick(String, run, "Stop", "Send"), Bool.pick(String, run, "interrupt", "send"), "claude · haiku", "", False{}, Nil{}, "haiku", "", "claude", Nil{}, "", Nil{},
    Nil{}, "", Nil{}, "", "", False{}, Nil{}, Nil{}, run)

def attr(as: List<&2, D.Attr>, +k: String) -> String:
  match as:
    case Nil{}: ""
    case D.At{+n, +v} <> t: Bool.pick(String, String.eq(n, k), v, attr(t, k))
    case _ <> t: attr(t, k)

def on(as: List<&2, D.Attr>) -> String:
  match as:
    case Nil{}: ""
    case D.On{"click", +a} <> _: a
    case _ <> t: on(t)

def text(ns: List<&2, D.Node>) -> String:
  match ns:
    case Nil{}: ""
    case D.Txt{s} <> t: s ++ text(t)
    case D.El{_, _, _, kids} <> t: text(kids) ++ text(t)
    case _ <> t: text(t)

# the send button ("<action> <label>") and the slash rows' names
def look(ns: List<&2, D.Node>) -> String:
  match ns:
    case Nil{}: ""
    case D.El{+tag, _, +as, +kids} <> t:
      Bool.pick(String, Bool.and(String.eq(tag, "button"), String.starts_with(attr(as, "class"), "primary")), "[" ++ on(as) ++ " " ++ text(kids) ++ "]",
        Bool.pick(String, String.eq(attr(as, "class"), "skill on") , "{" ++ attr(as, "data-value") ++ "}", Bool.pick(String, String.eq(attr(as, "class"), "skill"), "{" ++ attr(as, "data-value") ++ "}", ""))) ++ look(kids) ++ look(t)
    case _ <> t: look(t)

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("running, nothing typed: Stop", look(V.View.local(comp("", True{}), "")), "[interrupt Stop]")
    C.Check.str("running, typed before the hub knows: Steer at once", look(V.View.local(comp("", True{}), "also this")), "[send Steer]")
    C.Check.str("running, typed then cleared: Stop again", look(V.View.local(comp("also", True{}), "")), "[interrupt Stop]")
    C.Check.str("idle, typed: Send", look(V.View.local(comp("", False{}), "hi")), "[send Send]")
    C.Check.str("running, \"/b\": the slash commands at once", Bool.show(String.contains(look(V.View.local(comp("", True{}), "/b")), "{/btw}")), "True")
    C.Check.str("running, \"/btw q\": Ask, no rows", look(V.View.local(comp("/b", True{}), "/btw q")), "[send Ask]")
    C.Check.str("the hub's render for this draft is kept (here: no rows)", Bool.show(String.contains(look(V.View.local(comp("/b", True{}), "/b")), "{/btw}")), "False")
