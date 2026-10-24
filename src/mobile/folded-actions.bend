import Base
import ../core/json.bend as J

# A folded shelf still carries its real rows (IDs, titles, hierarchy, counts
# and current status). Its swipe controls cannot be used until it is opened.
# Do not duplicate their labels/options in both native screen projections.
# The next opened-shelf read renders all controls from current canonical state.
def Folded.row.fields(fs: J.Json) -> J.Json:
  match fs:
    case J.Field{"lead", _, tail}: J.Field{"lead", J.Arr{J.End{}}, Folded.row.fields(tail)}
    case J.Field{"trail", _, tail}: J.Field{"trail", J.Arr{J.End{}}, Folded.row.fields(tail)}
    case J.Field{k, v, tail}: J.Field{k, v, Folded.row.fields(tail)}
    case other: other

def Folded.row(j: J.Json) -> J.Json:
  match j:
    case J.Obj{fs}: J.Obj{Folded.row.fields(fs)}
    case other: other

def Folded.rows.items(xs: J.Json) -> J.Json:
  match xs:
    case J.Item{h, t}: J.Item{Folded.row(h), Folded.rows.items(t)}
    case other: other

def Folded.rows(open: Bool, j: J.Json) -> J.Json:
  match open j:
    case False{} J.Arr{xs}: J.Arr{Folded.rows.items(xs)}
    case _ other: other

def Folded.project.value(k: String, v: J.Json, +p: J.Json) -> J.Json:
  match k:
    case "settled": Folded.rows(J.Json.get_bool(p, "open", False{}), v)
    case "archived": Folded.rows(J.Json.get_bool(p, "archOpen", False{}), v)
    case _: v

def Folded.project.fields(fs: J.Json, +p: J.Json) -> J.Json:
  match fs:
    case J.Field{+k, v, tail}: J.Field{k, Folded.project.value(k, v, p), Folded.project.fields(tail, p)}
    case other: other

def Folded.project(+j: J.Json) -> J.Json:
  match j:
    case J.Obj{fs}: J.Obj{Folded.project.fields(fs, j)}
    case other: other

def Folded.projects(xs: J.Json) -> J.Json:
  match xs:
    case J.Item{h, t}: J.Item{Folded.project(h), Folded.projects(t)}
    case other: other

def Folded.screen.fields(fs: J.Json) -> J.Json:
  match fs:
    case J.Field{"projects", J.Arr{xs}, tail}: J.Field{"projects", J.Arr{Folded.projects(xs)}, Folded.screen.fields(tail)}
    case J.Field{k, v, tail}: J.Field{k, v, Folded.screen.fields(tail)}
    case other: other

def Folded.screen(j: J.Json) -> J.Json:
  match j:
    case J.Obj{fs}: J.Obj{Folded.screen.fields(fs)}
    case other: other
