import Base
import ./http.bend as H
import ./utf8.bend as U8
import ./sha256.bend as SH

# a token compared in constant time (sha256.bend's Ct.eq): the time a
# compare takes says nothing of how much of a guess was right
def Auth.same(+a: String, +b: String) -> Bool:
  Bool.and(Nat.is_eq(List.length(&2, U32, U8.Utf8.encode(a)), List.length(&2, U32, U8.Utf8.encode(b))), SH.Ct.eq(U8.Utf8.encode(a), U8.Utf8.encode(b)))

# Credentials are complete field values, never substrings of another field.
def Auth.cookie.go(xs: List<&2, String>, +token: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case +x <> t:
      Bool.or(Auth.same(String.trim(x), "bp_token=" ++ token), Auth.cookie.go(t, token))

def Auth.credential(+hs: List<&2, H.Header>, +path: String, +token: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(token)), Bool.or(
    Auth.same(H.Http.header_of(hs, "authorization"), "Bearer " ++ token), Bool.or(
      Auth.same(H.Http.param(path, "token"), token),
      Auth.cookie.go(String.split(H.Http.header_of(hs, "cookie"), ';'), token))))

# Browsers serialize Origin as scheme://authority, with no path or userinfo.
# An absent Origin supports native clients; Fetch Metadata still rejects sites.
def Auth.origin(+origin: String, +host: String) -> Bool:
  Bool.or(String.is_empty(origin), Bool.and(Bool.not(String.is_empty(host)), Bool.or(
    String.eq(String.to_lower(origin), "http://" ++ String.to_lower(host)),
    String.eq(String.to_lower(origin), "https://" ++ String.to_lower(host)))))

def Auth.browser(+hs: List<&2, H.Header>) -> Bool:
  Bool.and(Auth.origin(H.Http.header_of(hs, "origin"), H.Http.header_of(hs, "host")),
    Bool.not(String.eq(String.to_lower(H.Http.header_of(hs, "sec-fetch-site")), "cross-site")))

# A browser cannot use DNS rebinding to inherit a localhost exemption.
def Auth.local.host(+host: String) -> Bool:
  Bool.or(String.eq(host, "localhost"), Bool.or(String.starts_with(host, "localhost:"),
    Bool.or(String.eq(host, "127.0.0.1"), Bool.or(String.starts_with(host, "127.0.0.1:"),
      Bool.or(String.eq(host, "[::1]"), String.starts_with(host, "[::1]:"))))))

def Auth.trusted(+trusted: Bool, +hs: List<&2, H.Header>) -> Bool:
  Bool.and(trusted, Bool.and(String.is_empty(H.Http.header_of(hs, "tailscale-user-login")),
    Bool.or(Auth.local.host(String.to_lower(H.Http.header_of(hs, "host"))),
      Bool.and(String.is_empty(H.Http.header_of(hs, "host")), String.is_empty(H.Http.header_of(hs, "origin"))))))

# Every client presents the pairing token. Before, the owner's tailnet
# devices (Tailscale's whois) and this machine's programs (loopback) were
# let in without it, Host saying localhost, which any program can send.
# Those are still let in, the legacy way, while clients move to the token:
# the hub tells such a client to pair again and logs it (server.bend's
# Conn.legacy). Auth.legacy.on() turning False ends the legacy way.
def Auth.legacy.on() -> Bool:
  True{}

def Auth.allowed(+trusted: Bool, +hs: List<&2, H.Header>, +path: String, +token: String) -> Bool:
  Bool.and(Auth.browser(hs), Bool.or(Bool.and(Auth.legacy.on(), Auth.trusted(trusted, hs)), Auth.credential(hs, path, token)))

# let in the legacy way: allowed, and without the token
def Auth.legacy(+trusted: Bool, +hs: List<&2, H.Header>, +path: String, +token: String) -> Bool:
  Bool.and(Auth.allowed(trusted, hs, path, token), Bool.not(Auth.credential(hs, path, token)))

# An agent's MCP endpoint (/mcp/<seg>, server.bend's Hub.mcp_url) takes a
# key of its own instead of the token: the token's HMAC of the segment
# (the thread, and the process's generation), so the token stays out of
# agents' arguments and a key opens that one thread's tools
def Auth.mcp.key(+token: String, +seg: String) -> String:
  SH.Hex.encode(SH.Hmac.sha256(U8.Utf8.encode(token), U8.Utf8.encode("mcp\n" ++ seg)))

def Auth.mcp.keyed(+path: String, +token: String, +seg: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(token)), Auth.same(H.Http.param(path, "k"), Auth.mcp.key(token, seg)))

def Auth.mcp(+trusted: Bool, +hs: List<&2, H.Header>, +path: String, +token: String, +seg: String) -> Bool:
  Bool.or(Auth.allowed(trusted, hs, path, token), Bool.and(Auth.browser(hs), Auth.mcp.keyed(path, token, seg)))

# an MCP call let in the legacy way: neither the token nor the key
def Auth.mcp.legacy(+trusted: Bool, +hs: List<&2, H.Header>, +path: String, +token: String, +seg: String) -> Bool:
  Bool.and(Auth.legacy(trusted, hs, path, token), Bool.not(Auth.mcp.keyed(path, token, seg)))

# Pairing never inherits the localhost exemption; it proves the shared secret.
def Auth.pair(+hs: List<&2, H.Header>, +token: String) -> Bool:
  Bool.and(Auth.browser(hs), Bool.and(Bool.not(String.is_empty(token)),
    Auth.same(H.Http.header_of(hs, "authorization"), "Bearer " ++ token)))

def Auth.cookie(+token: String, https: Bool) -> String:
  "Set-Cookie: bp_token=" ++ token ++ "; Path=/; HttpOnly; SameSite=Strict; Max-Age=31536000" ++ Bool.pick(String, https, "; Secure", "") ++ "\r\n"
