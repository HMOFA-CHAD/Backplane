import Base
import ../core/client.bend as U
import ../core/model.bend as M
import ../core/json.bend as J
import ../core/presentation.bend as P
import ../core/thin-wire.bend as W

# Private, per-connection sidebar identity. Canonical sequence, all recipient
# info/live data, clock, scope and every transient UI input are retained.
# Only request/model-rehydration counters and five main-panel-only fields are omitted.
# No key or draft value is included in a response or diagnostic.
def Sidebar.omit(+key: String) -> Bool:
  Bool.or(String.eq(key, "@settings.page"), Bool.or(String.eq(key, "@set.sc"), String.eq(key, "@set.focus")))

def Sidebar.drafts(xs: List<&2, Sigma<&2, &2, String, _ => String>>) -> List<&2, J.KV>:
  match xs:
    case Nil{}: Nil{}
    case (+k, v) <> rest:
      List.append(&2, J.KV, Bool.pick(List<&2, J.KV>, Sidebar.omit(k), Nil{}, [J.KV{k, J.Str{v}}]), Sidebar.drafts(rest))

def Sidebar.flags(xs: List<&2, Sigma<&2, &2, String, _ => Bool>>) -> List<&2, J.KV>:
  match xs:
    case Nil{}: Nil{}
    case (+k, v) <> rest:
      List.append(&2, J.KV, Bool.pick(List<&2, J.KV>, Bool.or(String.eq(k, "settings"), String.eq(k, "pairqr")), Nil{}, [J.KV{k, J.Flag{v}}]), Sidebar.flags(rest))

# Info.put.models increments this native-memo counter even for an identical
# catalog on rehydration. Web sidebar reads neither counter; actual model
# content and every other info field remain part of the exact private key.
def Sidebar.info(xs: List<&2, Sigma<&2, &2, String, _ => String>>) -> List<&2, J.KV>:
  match xs:
    case Nil{}: Nil{}
    case (+k, v) <> rest:
      List.append(&2, J.KV, Bool.pick(List<&2, J.KV>, String.eq(k, "models.v"), Nil{}, [J.KV{k, J.Str{v}}]), Sidebar.info(rest))

def Sidebar.key(u: U.Ui, epoch: String, view: String) -> String:
  match u:
    case U.Ui{st, sel, dr, live, op, on, now, ad, pa, version, _, want, error, note, nf, outbox, _}:
      J.Json.show(J.Json.obj([J.KV{"epoch", J.Str{epoch}}, J.KV{"view", J.Str{view}}, J.KV{"seq", J.Json.nat(M.State.seq(st))},
        J.KV{"sel", J.Str{sel}}, J.KV{"drafts", J.Json.obj(Sidebar.drafts(Map.to_list(&2, String, dr)))},
        J.KV{"live", J.Json.obj(P.Session.strings(Map.to_list(&2, String, live)))}, J.KV{"open", J.Json.obj(Sidebar.flags(Map.to_list(&2, Bool, op)))},
        J.KV{"online", J.Flag{on}}, J.KV{"clock", J.Json.nat(now)}, J.KV{"adding", J.Flag{ad}}, J.KV{"panel", J.Flag{pa}}, J.KV{"version", J.Str{version}},
        J.KV{"want", J.Flag{want}}, J.KV{"error", J.Str{error}}, J.KV{"note", J.Str{note}},
        J.KV{"info", J.Json.obj(Sidebar.info(Map.to_list(&2, String, nf)))}, J.KV{"outbox", J.Json.obj(P.Session.strings(Map.to_list(&2, String, outbox)))}]))

def Sidebar.bounded(+key: String) -> Bool:
  W.Wire.within(key, 32768n)

# Limit reuse to Settings actions and refreshes while Settings is visible.
# Normal actions/commands still execute once before any region is reused.
def Sidebar.request(+p: J.Json, +u: U.Ui) -> Bool:
  +action = J.Json.get_str(p, "action", "")
  Bool.or(Bool.and(String.eq(action, "flag"), String.eq(J.Json.get_str(p, "value", ""), "settings")),
    Bool.or(String.eq(action, "settings-page"), Bool.and(String.is_empty(action), U.Ui.flag(u, "settings"))))
