import Base
import ../src/core/google.bend as G
import ./check.bend as C

def show(b: Bool) -> String:
  Bool.pick(String, b, "yes", "no")

def forwarded(+url: String, +query: String) -> String:
  G.Google.hop("state=" ++ G.Google.state("nonce", url) ++ "&code=code" ++ query, "other")

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("tailnet origin", show(G.Google.hop.ok("https://box.tail1.ts.net")), "yes")
    C.Check.str("tailnet port", show(G.Google.hop.ok("http://box.tail1.ts.net:3787")), "yes")
    C.Check.str("tailnet uppercase hostname", show(G.Google.hop.ok("https://BOX.TAIL1.TS.NET:443")), "yes")
    C.Check.str("tailnet hyphen label", show(G.Google.hop.ok("https://my-box.tail1.ts.net")), "yes")
    C.Check.str("tailnet max port", show(G.Google.hop.ok("https://box.ts.net:65535")), "yes")
    C.Check.str("refuse foreign suffix", show(G.Google.hop.ok("https://box.ts.net.evil.invalid")), "no")
    C.Check.str("refuse userinfo", show(G.Google.hop.ok("https://evil.invalid@box.ts.net")), "no")
    C.Check.str("refuse origin path", show(G.Google.hop.ok("https://box.ts.net/path")), "no")
    C.Check.str("refuse origin query", show(G.Google.hop.ok("https://box.ts.net?q=x")), "no")
    C.Check.str("refuse origin fragment", show(G.Google.hop.ok("https://box.ts.net#x")), "no")
    C.Check.str("refuse backslash", show(G.Google.hop.ok("https://evil.invalid\\box.ts.net")), "no")
    C.Check.str("refuse empty label", show(G.Google.hop.ok("https://box..ts.net")), "no")
    C.Check.str("refuse label leading hyphen", show(G.Google.hop.ok("https://-box.ts.net")), "no")
    C.Check.str("refuse label trailing hyphen", show(G.Google.hop.ok("https://box-.ts.net")), "no")
    C.Check.str("refuse empty port", show(G.Google.hop.ok("https://box.ts.net:")), "no")
    C.Check.str("refuse zero port", show(G.Google.hop.ok("https://box.ts.net:0")), "no")
    C.Check.str("refuse overflowing port", show(G.Google.hop.ok("https://box.ts.net:65536")), "no")
    C.Check.str("refuse wrapping port integer", show(G.Google.hop.ok("https://box.ts.net:4294967297")), "no")
    C.Check.str("refuse signed port", show(G.Google.hop.ok("https://box.ts.net:+443")), "no")
    C.Check.str("refuse multiple ports", show(G.Google.hop.ok("https://box.ts.net:443:80")), "no")
    C.Check.str("refuse CRLF in authority", forwarded("http://box.ts.net:3787\r\nX-Test: injected", ""), "")
    C.Check.str("refuse LF in host", forwarded("http://box\n.ts.net", ""), "")
    C.Check.str("refuse tab in host", forwarded("http://box\t.ts.net", ""), "")
    C.Check.str("refuse space in authority", forwarded("http://box .ts.net", ""), "")
    C.Check.str("refuse encoded control in authority", forwarded("http://box%0d%0a.ts.net", ""), "")
    C.Check.str("refuse raw query CRLF", forwarded("http://box.ts.net:3787", "\r\nX-Test: injected"), "")
    C.Check.str("refuse raw query tab", forwarded("http://box.ts.net:3787", "\t"), "")
    C.Check.str("refuse raw query NUL", forwarded("http://box.ts.net:3787", SCon{Chr{0}, SNil{}}), "")
    C.Check.str("refuse raw fragment before one-hop marker", forwarded("http://box.ts.net:3787", "&note=#fragment"), "")
    C.Check.str("keep encoded fragment character as query data", forwarded("http://box.ts.net:3787", "&note=%23fragment"), "http://box.ts.net:3787/oauth/google?state=" ++ G.Google.state("nonce", "http://box.ts.net:3787") ++ "&code=code&note=%23fragment&hop=1")
    C.Check.str("preserve existing one-hop guard", forwarded("http://box.ts.net:3787", "&hop=1"), "")
    C.Check.str("preserve legitimate forwarding", forwarded("http://box.ts.net:3787", ""), "http://box.ts.net:3787/oauth/google?state=" ++ G.Google.state("nonce", "http://box.ts.net:3787") ++ "&code=code&hop=1")
