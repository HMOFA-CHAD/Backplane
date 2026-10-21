import Base
import ./check.bend as C
import ../src/server/thin-view.bend as V
import ../src/web/dom.bend as D
import ../src/web/presentation.bend as W
import ../src/core/json.bend as J

def same(+name: String, got: D.Node, want: D.Node) -> IO(Unit):
  C.Check.str(name, J.Json.show(W.Node.write(got)), J.Json.show(W.Node.write(want)))

def main() -> IO(Unit):
  do IO<Unit>:
    +before : D.Node = D.Dom.button("earlier", "view-page", "", "More", "More")
    +after : D.Node = D.Dom.button("thin-message-more", "thin-message-more", "m", "More", "More")
    +timeline : D.Node = D.El{"div", "timeline", [D.At{"class", "timeline"}, D.At{"id", "timeline"}], [D.Txt{"message"}]}
    +wanted : D.Node = D.El{"div", "timeline", [D.At{"class", "timeline"}, D.At{"id", "timeline"}], [before, D.Txt{"message"}, after]}
    same("controls are inside exact timeline in older/message/continuation order", V.Render.timeline(timeline, [before], [after]), wanted)
    +root : D.Node = D.El{"div", "app", [D.At{"class", "app"}], [D.Txt{"header"}, timeline, D.Txt{"composer"}]}
    same("original app root key attrs and siblings are unchanged", V.Render.timeline(root, [before], [after]), D.El{"div", "app", [D.At{"class", "app"}], [D.Txt{"header"}, wanted, D.Txt{"composer"}]})
    same("no controls leaves original timeline exact", V.Render.timeline(root, Nil{}, Nil{}), root)
    same("views without a timeline gain no outer controls or wrapper", V.Render.timeline(D.Dom.div("mailroom", [D.Txt{"mail"}]), [before], [after]), D.Dom.div("mailroom", [D.Txt{"mail"}]))
    same("timeline class alone cannot redirect controls", V.Render.timeline(D.Dom.div("timeline", [D.Txt{"other"}]), [before], [after]), D.Dom.div("timeline", [D.Txt{"other"}]))
    same("text nodes retain exact Unicode", V.Render.timeline(D.Txt{"日本語🙂"}, [before], [after]), D.Txt{"日本語🙂"})
