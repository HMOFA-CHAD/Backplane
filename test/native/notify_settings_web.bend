import Base
import ../../src/core/json.bend as J
import ../../src/core/client.bend as U
import ../../src/core/model.bend as M
import ../../src/web/dom.bend as D
import ../../src/web/view.bend as W

# Emit the real web Settings DOM for a headless snapshot with style.css.
def attrs(as: List<&2, D.Attr>) -> List<&2, J.KV>:
  match as:
    case Nil{}:
      Nil{}
    case D.At{k, v} <> t:
      J.KV{k, J.Str{v}} <> attrs(t)
    case D.On{e, a} <> t:
      J.KV{"data-action-" ++ e, J.Str{a}} <> attrs(t)

def nodes(ns: List<&2, D.Node>) -> List<&2, J.Json>:
  match ns:
    case Nil{}:
      Nil{}
    case D.Txt{s} <> t:
      J.Json.obj([J.KV{"text", J.Str{s}}]) <> nodes(t)
    case D.El{tag, _, as, kids} <> t:
      J.Json.obj([J.KV{"tag", J.Str{tag}}, J.KV{"attrs", J.Json.obj(attrs(as))}, J.KV{"kids", J.Json.arr(nodes(kids))}]) <> nodes(t)

def main() -> IO(Unit):
  IO.print(J.Json.show(J.Json.arr(nodes([W.View.settings(U.Ui.init(0n), M.State.empty(), Map.new(&2, String), "test", "")]))))
