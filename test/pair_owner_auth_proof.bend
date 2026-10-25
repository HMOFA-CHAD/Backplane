import Base
import ../src/core/auth.bend as AUTH
import ../src/core/http.bend as HTTPAUTH

# ---- native owner tailnet pairing: route-only, own-authority trust ----
law auth_owner_pair_untrusted:
  for own: List<&2, String>
  for hs: List<&2, HTTPAUTH.Header>
  for method: String
  for path: String
  {AUTH.Auth.owner.pair(False{}, own, hs, method, path) == False{} : Bool}

law auth_owner_pair_routes:
  {[AUTH.Auth.owner.pair(True{}, ["100.64.0.8:3787"], [HTTPAUTH.Header{"host", "100.64.0.8:3787"}], "POST", "/bots/pair"),
    AUTH.Auth.owner.pair(True{}, ["100.64.0.8:3787"], [HTTPAUTH.Header{"host", "100.64.0.8:3787"}], "POST", "/mcp/t1")] == [True{}, False{}] : List<&2, Bool>}

law auth_owner_pair_rebound:
  {AUTH.Auth.owner.pair(True{}, ["100.64.0.8:3787"], [HTTPAUTH.Header{"host", "attacker.invalid:3787"}], "POST", "/bots/pair") == False{} : Bool}
# ---- end native owner tailnet pairing ----

# ---- native owner tailnet pairing ----
def auth_owner_pair_untrusted(own, hs, method, path): {==}
def auth_owner_pair_routes(): {==}
def auth_owner_pair_rebound(): {==}
# ---- end native owner tailnet pairing ----
