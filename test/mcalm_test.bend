import Base
import ./check.bend as C
import ./mbots_test.bend as Bots
import ../src/core/json.bend as J
import ../src/mobile/hubs.bend as H

# A phone's saved state loaded at launch (Hubs.stale) never puts a sheet,
# menu, form or error back over the app: the state may have been saved
# while one was up. What the person had selected stays.
def act(+h: H.Hubs, +a: String, +v: String) -> H.Hubs:
  H.Hubs.after(H.Hubs.act(h, a, v))

def none(j: J.Json) -> Bool:
  match j:
    case J.Null{}:
      True{}
    case _:
      False{}

def up(+s: J.Json, +k: String) -> String:
  Bool.show(Bool.not(none(J.Json.get_obj(s, k))))

def opened() -> H.Hubs:
  act(act(act(Bots.two(), "find-open", "search"), "flag", "settings"), "bot-new", "")

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("find up before", up(H.Hubs.screen(opened()), "find"), "True")
    C.Check.str("settings up before", up(H.Hubs.screen(opened()), "settings"), "True")
    C.Check.str("bot form up before", up(H.Hubs.screen(opened()), "newBot"), "True")
    C.Check.str("find shut after load", up(H.Hubs.screen(H.Hubs.stale(opened())), "find"), "False")
    C.Check.str("settings shut after load", up(H.Hubs.screen(H.Hubs.stale(opened())), "settings"), "False")
    C.Check.str("bot form shut after load", up(H.Hubs.screen(H.Hubs.stale(opened())), "newBot"), "False")
    C.Check.str("error cleared after load", J.Json.get_str(H.Hubs.screen(H.Hubs.stale(opened())), "error", ""), "")
    C.Check.str("selection kept", J.Json.get_str(H.Hubs.screen(H.Hubs.stale(act(opened(), "select", "box:3787|t1"))), "sel", "x"),
      J.Json.get_str(H.Hubs.screen(act(opened(), "select", "box:3787|t1")), "sel", "y"))
    IO.print("mobile calm-on-load tests passed\n")
