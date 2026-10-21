import Base
import ./check.bend as C
import ../src/server/thin-view.bend as V
import ../src/core/model.bend as M
import ../src/core/client.bend as U
import ../src/core/json.bend as J
import ../src/core/botui.bend as BI

def obj(s: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(s), J.Null{})

def state() -> M.State:
  M.State.replay([M.ThreadCreated{"t", "", "Kit", M.Local{}, "", "", "codex", "", 1n}, M.BotSet{"b", "Kit", "t", 0n, "", 1n}, M.UberSet{"b", "u", 2n}], M.State.empty())

def target() -> J.Json:
  V.Target.json("bot", "b")

def request(tab: String) -> J.Json:
  J.Json.obj([J.KV{"hub", J.Str{"h"}}, J.KV{"cid", J.Str{"cid"}}, J.KV{"nativeRenderer", J.Str{"ios-v1"}}, J.KV{"target", target()},
    J.KV{"session", J.Json.obj([J.KV{"sel", J.Str{"t"}}, J.KV{"rid", J.Num{"10"}}, J.KV{"drafts", obj("{}")}, J.KV{"route", V.Route.json("b", tab)}])}])

def current(+p: J.Json) -> U.Ui:
  V.Session.current(False{}, state(), obj("{}"), obj("{}"), 10n, p)

def tab(name: String) -> String:
  BI.BU.tab.of(current(request(name)), "b")

def count(a: V.ActResult) -> String:
  match a:
    case V.ActResult{_, cmds}: Nat.show(List.length(&2, J.Json, cmds))

def check(name: String, b: Bool) -> IO(Unit):
  C.Check.str(name, Bool.pick(String, b, "yes", "no"), "yes")

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("initial Browser preference restores actual route", tab("browser"), "browser")
    C.Check.str("initial Space preference restores actual route", tab("space"), "space")
    C.Check.str("old Tasks content id survives nested bar", tab("tasks"), "tasks")
    C.Check.str("old Hooks content id survives nested bar", tab("hooks"), "hooks")
    C.Check.str("old Status content id survives nested bar", tab("status"), "status")
    C.Check.str("route pack reports actual current content id", J.Json.get_str(J.Json.get_obj(V.Route.pack(current(request("tasks"))), "route"), "tab", ""), "tasks")
    C.Check.str("route pack retains exact owning bot", J.Json.get_str(J.Json.get_obj(V.Route.pack(current(request("browser"))), "route"), "bot", ""), "b")
    check("route is valid only for exact bot", Bool.not(V.Route.valid(V.Route.json("foreign", "browser"), target())))
    check("bot preference cannot attach to thread", Bool.not(V.Route.valid(V.Route.json("b", "browser"), V.Target.json("thread", "b"))))
    check("unknown route rejected", Bool.not(V.Route.valid(V.Route.json("b", "unknown"), target())))
    check("extra field rejected", Bool.not(V.Route.valid(V.Obj.put(V.Route.json("b", "browser"), "token", J.Str{"x"}), target())))
    C.Check.str("unsupported route normalizes through canonical default", tab("unknown"), "mail")
    C.Check.str("absent native renderer cannot enable typed Mailroom", U.Ui.info(current(V.Obj.put(request("mail"), "nativeRenderer", J.Str{"unknown"})), "local.mailroom"), "")
    C.Check.str("Android exact declared renderer supported", U.Ui.info(current(V.Obj.put(request("mail"), "nativeRenderer", J.Str{"android-v1"})), "local.mailroom"), "on")
    C.Check.str("iOS exact declared renderer supported", U.Ui.info(current(request("mail")), "local.mailroom"), "on")
    C.Check.str("initial route restoration issues no commands", count(V.Action.run(False{}, current(request("browser")), request("browser"), 10n)), "0")
    C.Check.str("normal result keeps canonical current thread", U.Ui.sel.of(current(request("space"))), "t")
    C.Check.str("route restore leaves authoritative state intact", Nat.show(List.length(&2, M.Thread, U.Ui.threads(state()))), "1")
    C.Check.str("reading anchor retains exact entry id", J.Json.get_str(V.Anchor.safe(obj("{\"id\":\"m\",\"offset\":7}")), "id", ""), "m")
    C.Check.str("reading anchor retains exact offset", Nat.show(J.Json.get_nat(V.Anchor.safe(obj("{\"id\":\"m\",\"offset\":7}")), "offset", 0n)), "7")
    C.Check.str("unsafe reading offset resets without coercion", Nat.show(J.Json.get_nat(V.Anchor.safe(obj("{\"id\":\"m\",\"offset\":\"7\"}")), "offset", 9n)), "0")
    C.Check.str("reading anchor strips unrelated private fields", J.Json.get_str(V.Anchor.safe(obj("{\"id\":\"m\",\"offset\":7,\"token\":\"not-carried\"}")), "token", "absent"), "absent")
