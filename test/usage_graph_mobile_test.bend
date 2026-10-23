import Base
import ./usage_graph_test.bend as F
import ../src/core/client.bend as U
import ../src/core/json.bend as J
import ../src/mobile/screen.bend as S
import ../src/mobile/hubs.bend as H
import ../src/core/i18n.bend as I

def native() -> String:
  J.Json.show(J.Json.arr(S.Mob.usage.page(I.En{}, F.ui())))

def scope() -> String:
  +hs = H.Hubs{"fixture", 1792359200n, "a", [H.Hub{"a", F.ui()}, H.Hub{"b", F.ui()}]}
  +changed = H.Hubs.after(H.Hubs.act(hs, "usage-provider", "b|codex"))
  U.Usage.page.provider(H.Hubs.ui(changed, "a")) ++ "/" ++ U.Usage.page.provider(H.Hubs.ui(changed, "b"))

def missing_scope() -> String:
  +hs = H.Hubs{"fixture", 1792359200n, "a", [H.Hub{"a", F.ui()}]}
  +changed = H.Hubs.after(H.Hubs.act(hs, "usage-provider", "missing|codex"))
  U.Usage.page.provider(H.Hubs.ui(changed, "a"))
