import Base
import ../src/server/desktop-broker.bend as B
import ../src/core/json.bend as J

def check(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.print("ok actual connection hello uses live canonical identity")
    case False{}: IO.die(Unit, 1, "FAIL actual connection hello uses live canonical identity")

def main() -> IO(Unit):
  do IO<Unit>:
    +out : Chan(String) <- Chan.new(String, 4)
    +ev : Chan(String) <- Chan.new(String, 4)
    +b : B.Broker <- B.Broker.link("connected", B.Broker.empty(), 1,
      "{\"version\":\"fixture-version\",\"hub\":\"persisted-machine-A\"}",
      out, "epoch-A", "lease-A", "",
      "{\"version\":\"fixture-version\",\"hub\":\"\"}", ev)
    check(String.eq(J.Json.get_str(B.Broker.hello_payload(b, "{\"version\":\"fixture-version\",\"hub\":\"\"}"), "hub", ""), "persisted-machine-A"))
