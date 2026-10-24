import Base
import ./check.bend as C
import ./sidebar_wire_test.bend as F
import ../src/core/json.bend as J
import ../src/server/thin-sidebar-wire.bend as W
import ../src/web/sidebar-slot.bend as S

law full_identity:
  for shown: J.Json
  {W.Region.shown(False{}, shown) == shown : J.Json}
def full_identity(shown): {==}
law shown_exact:
  for +reuse: Bool
  for +shown: J.Json
  {W.Region.shown(reuse, shown) == Bool.pick(J.Json, reuse, W.Region.replace.go(shown, S.Slot.is(shown, "aside")), shown) : J.Json}
def shown_exact(reuse, shown):
  match reuse:
    case False{}: {==}
    case True{}: {==}

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("full shown remains byte exact", J.Json.show(W.Region.shown(False{}, F.picture())), J.Json.show(F.picture()))
    C.Check.str("reference shown keeps original rewrite", J.Json.show(W.Region.shown(True{}, F.picture())), J.Json.show(W.Region.replace.go(F.picture(), False{})))
    C.Check.str("full retains actual sidebar", J.Json.show(S.Slot.sidebar(J.Json.get_obj(W.Region.result(False{}, F.picture(), "7"), "shown"))), J.Json.show(F.sidebar()))
    C.Check.str("full receipt retains fresh token", J.Json.get_str(J.Json.get_obj(W.Region.result(False{}, F.picture(), "7"), "sidebarRegion"), "token", ""), "7")
    C.Check.str("full receipt has no base", J.Json.get_str(J.Json.get_obj(W.Region.result(False{}, F.picture(), "7"), "sidebarRegion"), "base", "bad"), "")
    C.Check.str("reference receipt retains same base", J.Json.get_str(J.Json.get_obj(W.Region.result(True{}, F.picture(), "7"), "sidebarRegion"), "base", ""), "7")
