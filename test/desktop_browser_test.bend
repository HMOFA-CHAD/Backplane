import Base
import ../src/core/desktop-browser.bend as D
import ../src/core/http.bend as H
import ../src/core/json.bend as J

def check(name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.print("ok " ++ name)
    case False{}: IO.die(Unit, 1, "FAIL " ++ name)

def headers(auth: String) -> List<&2, H.Header>:
  [H.Header{"host", "127.0.0.1:3787"}, H.Header{"upgrade", "websocket"}, H.Header{"authorization", auth}]

def target() -> D.Target:
  D.Target{"owner-A", "guest-A", 2n}

def grant(drive: String, recording: Bool) -> D.Grant:
  D.Grant{"epoch-A", "controller-A", target(), 7n, 3000n, drive, recording}

def agent(g: D.Grant, t: D.Target, rev: Nat, now: Nat, method: String) -> Bool:
  D.Desktop.agent(g, "epoch-A", "controller-A", t, rev, now, method)

def parse(s: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(s), J.Null{})

def main() -> IO(Unit):
  do IO<Unit>:
    check("strict main header accepted", D.Desktop.auth("127.0.0.1", "GET", "/desktop/browser/v1", headers("Bearer secret"), "secret"))
    check("localhost has no token exemption", Bool.not(D.Desktop.auth("127.0.0.1", "GET", "/desktop/browser/v1", [H.Header{"host", "127.0.0.1"}, H.Header{"upgrade", "websocket"}], "secret")))
    check("cookie is not broker authority", Bool.not(D.Desktop.auth("127.0.0.1", "GET", "/desktop/browser/v1", [H.Header{"host", "127.0.0.1"}, H.Header{"upgrade", "websocket"}, H.Header{"cookie", "bp_token=secret"}], "secret")))
    check("query credentials refused", Bool.not(D.Desktop.auth("127.0.0.1", "GET", "/desktop/browser/v1?token=secret", headers("Bearer secret"), "secret")))
    check("wrong bearer refused", Bool.not(D.Desktop.auth("127.0.0.1", "GET", "/desktop/browser/v1", headers("Bearer wrong"), "secret")))
    check("empty configured token refused", Bool.not(D.Desktop.auth("127.0.0.1", "GET", "/desktop/browser/v1", headers("Bearer "), "")))
    check("remote peer refused even with token", Bool.not(D.Desktop.auth("100.1.2.3", "GET", "/desktop/browser/v1", headers("Bearer secret"), "secret")))
    check("browser origin refused with valid token", Bool.not(D.Desktop.auth("127.0.0.1", "GET", "/desktop/browser/v1", H.Header{"origin", "http://127.0.0.1:3787"} <> headers("Bearer secret"), "secret")))
    check("duplicate authorization refused", Bool.not(D.Desktop.auth("127.0.0.1", "GET", "/desktop/browser/v1", H.Header{"authorization", "Bearer secret"} <> headers("Bearer secret"), "secret")))
    check("POST refused", Bool.not(D.Desktop.auth("127.0.0.1", "POST", "/desktop/browser/v1", headers("Bearer secret"), "secret")))
    check("exact guest command allowed", agent(grant("agent", False{}), target(), 7n, 100n, "Runtime.evaluate"))
    check("foreign owner refused", Bool.not(agent(grant("agent", False{}), D.Target{"owner-B", "guest-A", 2n}, 7n, 100n, "Runtime.evaluate")))
    check("foreign tab refused", Bool.not(agent(grant("agent", False{}), D.Target{"owner-A", "guest-B", 2n}, 7n, 100n, "Runtime.evaluate")))
    check("stale generation refused", Bool.not(agent(grant("agent", False{}), D.Target{"owner-A", "guest-A", 1n}, 7n, 100n, "Runtime.evaluate")))
    check("stale grant revision refused", Bool.not(agent(grant("agent", False{}), target(), 6n, 100n, "Runtime.evaluate")))
    check("deadline exact boundary refuses", Bool.not(agent(grant("agent", False{}), target(), 7n, 3000n, "Runtime.evaluate")))
    check("service restart epoch refuses", Bool.not(D.Desktop.agent(grant("agent", False{}), "epoch-B", "controller-A", target(), 7n, 100n, "Runtime.evaluate")))
    check("replaced controller refuses", Bool.not(D.Desktop.agent(grant("agent", False{}), "epoch-A", "controller-B", target(), 7n, 100n, "Runtime.evaluate")))
    check("person grant cannot drive CDP", Bool.not(agent(grant("person", True{}), target(), 7n, 100n, "Input.insertText")))
    check("agent grant cannot enable person input", Bool.not(D.Desktop.person(grant("agent", False{}), "epoch-A", "controller-A", target(), 7n, 100n)))
    check("person input separate authority", D.Desktop.person(grant("person", False{}), "epoch-A", "controller-A", target(), 7n, 100n))
    check("recording independent explicit grant", D.Desktop.record(grant("person", True{}), "epoch-A", "controller-A", target(), 7n, 100n))
    check("installed code does not imply recording", Bool.not(D.Desktop.record(grant("person", False{}), "epoch-A", "controller-A", target(), 7n, 100n)))
    check("global Browser endpoint refused", Bool.not(agent(grant("agent", False{}), target(), 7n, 100n, "Browser.getVersion")))
    check("Target escape refused", Bool.not(agent(grant("agent", False{}), target(), 7n, 100n, "Target.attachToTarget")))
    check("file upload has no implicit grant", Bool.not(agent(grant("agent", False{}), target(), 7n, 100n, "DOM.setFileInputFiles")))
    check("arbitrary init script has no public grant", Bool.not(agent(grant("agent", False{}), target(), 7n, 100n, "Page.addScriptToEvaluateOnNewDocument")))
    check("unknown owner cannot drive", String.eq(D.Desktop.drive(False{}, ""), "none"))
    check("canonical takeover is person", String.eq(D.Desktop.drive(True{}, "takeover"), "person"))
    check("canonical teach is person", String.eq(D.Desktop.drive(True{}, "teach"), "person"))
    check("canonical handback is agent", String.eq(D.Desktop.drive(True{}, ""), "agent"))
    check("target numeric generation", D.Target.valid(parse("{\"owner\":\"A\",\"tabId\":\"t\",\"generation\":2}")))
    check("target string generation refused", Bool.not(D.Target.valid(parse("{\"owner\":\"A\",\"tabId\":\"t\",\"generation\":\"2\"}"))))
    check("target fraction refused", Bool.not(D.Target.valid(parse("{\"owner\":\"A\",\"tabId\":\"t\",\"generation\":2.5}"))))
    check("duplicate root JSON key refused", Bool.not(D.Desktop.unique(parse("{\"owner\":\"A\",\"owner\":\"B\"}"), Nil{})))
    check("duplicate nested JSON key refused", Bool.not(D.Desktop.unique(parse("{\"payload\":{\"owner\":\"A\",\"owner\":\"B\"}}"), Nil{})))

    check("uint32 upper numeric identity accepted", D.Target.number(J.Num{"4294967295"}))
    check("numeric identity above uint32 refused", Bool.not(D.Target.number(J.Num{"4294967296"})))
    check("native immediate overflow identity refused before parse", Bool.not(D.Target.number(J.Num{"9007199254740991"})))
    check("huge numeric identity refused before parse", Bool.not(D.Target.number(J.Num{"999999999999999999999999999999999999999999999999999999999999999999999999999999"})))
    check("noncanonical numeric identity refused", Bool.not(D.Target.number(J.Num{"01"})))
    check("negative numeric identity refused", Bool.not(D.Target.number(J.Num{"-1"})))
    check("exponent identity refused", Bool.not(D.Target.number(J.Num{"1e9"})))
    check("invalid explicit target decodes safely without authority", D.Target.eq(D.Target.decode(parse("{\"owner\":\"A\",\"tabId\":\"x\",\"generation\":9007199254740991}")), D.Target{"A", "x", 0n}))
