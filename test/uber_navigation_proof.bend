import Base
import ../src/core/botui.bend as B

law uber_bar_order:
  {B.BU.nav.tabs() == ["chat", "mail", "space", "browser", "memory", "routines", "settings"] : List<&2, String>}
def uber_bar_order():
  {==}

law legacy_panel_parents:
  {(B.BU.nav.parent(B.BU.nav.tabs(), "status"), (B.BU.nav.parent(B.BU.nav.tabs(), "tasks"), B.BU.nav.parent(B.BU.nav.tabs(), "hooks"))) == ("mail", ("browser", "settings")) : String & (String & String)}
def legacy_panel_parents():
  {==}

law unfolded_routes_stay:
  for t: String
  {B.BU.nav.parent.k(False{}, t) == t : String}
def unfolded_routes_stay(t):
  {==}
