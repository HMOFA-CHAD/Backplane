import Base
import ./check.bend as C
import ../src/core/hub.bend as H
import ../src/core/model.bend as M
import ../src/core/mail.bend as ML
import ../src/core/mcp.bend as MCP
import ../src/core/json.bend as J
import ../src/core/mailcontinuity.bend as MCN

def request(+id: String) -> M.Change:
  M.MailPosted{id, "conv", "thread:worker", "bot:beta", "thread", "", "act", "Need a decision", 15n, 3n}

def reply(+conv: String) -> M.Change:
  M.MailPosted{"reply", conv, "bot:beta", "thread:worker", "thread", "", "fyi", "Decision supplied", 17n, 3n}

def base() -> M.State:
  M.State.replay([
    M.ThreadCreated{"foh", "", "Beta", M.Local{}, "", "/tmp/mail-continuity", "codex", "", 1n},
    M.ThreadCreated{"worker", "", "Worker", M.Local{}, "", "/tmp/mail-continuity", "codex", "", 1n},
    M.ThreadCreated{"run", "", "Mailroom", M.Local{}, "", "/tmp/mail-continuity", "codex", "", 1n},
    M.BotSet{"beta", "Beta", "foh", 0n, "", 1n}, M.SettingSet{"mail.on", "on", 1n},
    request("m1"), M.RunSet{"run", "beta", "conv", "m1", 3n}, M.TurnChanged{"run", M.Running{}, 3n}], M.State.empty())

def finish(+s: M.State, turn: M.TurnState) -> H.Step:
  H.Run.after(s, 10n, H.Step{[M.MessagePosted{"run", "final", M.Assistant{}, "Approval required but policy is never; nothing was sent", 10n}, M.TurnChanged{"run", turn, 10n}], Nil{}})

def posts(+cs: List<&2, M.Change>, +th: String) -> Nat:
  match cs:
    case Nil{}: 0n
    case M.MessagePosted{+t, _, _, _, _} <> rest:
      Nat.add(Bool.pick(Nat, String.eq(t, th), 1n, 0n), posts(rest, th))
    case _ <> rest: posts(rest, th)

def forwarded_text(cs: List<&2, M.Change>) -> String:
  match cs:
    case Nil{}: ""
    case M.MessagePosted{"foh", _, _, text, _} <> _: text
    case _ <> rest: forwarded_text(rest)

def committed(os: List<&2, H.Out>) -> List<&2, M.Change>:
  match os:
    case Nil{}: Nil{}
    case H.MailAppend{_, _, cs} <> _: cs
    case _ <> rest: committed(rest)

def result_step(res: MCP.Res) -> H.Step:
  match res:
    case MCP.Res{_, _, st}: st

def check(+label: String, +s: M.State, expected: String) -> IO(Unit):
  C.Check.str(label, Nat.show(posts(H.Queue.changes(finish(s, M.Completed{})), "foh")), expected)

def main() -> IO(Unit):
  do IO<Unit>:
    check("denied tools cannot silently complete an actionable run", base(), "1")
    check("read/open is not handled", M.State.apply(base(), M.MailMarked{"beta", "conv", "open", 3n, 0n, 4n}), "1")
    check("unread is not handled", M.State.apply(base(), M.MailMarked{"beta", "conv", "unread", 0n, 0n, 4n}), "1")
    check("decision log alone is not a reply", M.State.apply(base(), M.DecisionLogged{"d", "beta", "conv", "run", "Choose blue", "known", 4n}), "1")
    check("durably committed reply suppresses fallback", M.State.apply(base(), reply("conv")), "0")
    check("reply in another conversation cannot clear this request", M.State.apply(base(), reply("other")), "1")
    check("new same-second request after reply remains owed", M.State.replay([reply("conv"), request("m2")], base()), "1")
    check("explicit done is respected", M.State.apply(base(), M.MailMarked{"beta", "conv", "done", 3n, 0n, 4n}), "0")
    check("explicit snooze is respected", M.State.apply(base(), M.MailMarked{"beta", "conv", "snoozed", 3n, 99n, 4n}), "0")
    check("accepted escalation suppresses duplicate report", M.State.apply(base(), M.SettingSet{"run.escalated.run", "m1", 4n}), "0")
    check("old escalation cannot consume a new same-second request", M.State.replay([M.SettingSet{"run.escalated.run", "m1", 4n}, request("m2")], base()), "1")
    +step : H.Step = finish(base(), M.Completed{})
    +after : M.State = M.State.replay(H.Queue.changes(step), base())
    C.Check.str("fallback records exact pending input", M.Setting.get(after, "run.forwarded.run", ""), "m1")
    C.Check.str("fallback includes failed final response", Bool.show(String.contains(forwarded_text(H.Queue.changes(step)), "nothing was sent")), "True")
    C.Check.str("fallback identifies original input", Bool.show(String.contains(forwarded_text(H.Queue.changes(step)), "Actionable input: m1")), "True")
    check("replayed completion cannot send twice", after, "0")
    C.Check.str("process failure also surfaces unresolved request", Nat.show(posts(H.Queue.changes(finish(base(), M.Failed{})), "foh")), "1")
    C.Check.str("explicit interruption does not restart work", Nat.show(posts(H.Queue.changes(finish(base(), M.Interrupted{})), "foh")), "0")
    check("mail off preserves legacy path", M.State.apply(base(), M.SettingSet{"mail.on", "off", 4n}), "0")
    +s : M.State = base()
    +r : ML.Run = Maybe.default(&2, ML.Run, ML.Box.run_of(M.State.mail(s), "run"), ML.Run{"", "", "", "", 0n, False{}})
    +esc : MCP.Res = MCP.Mcp.run.escalate(True{}, s, 4n, r, J.Json.obj([J.KV{"to", J.Str{"bot"}}, J.KV{"text", J.Str{"Choose a source"}}]))
    check("production escalation records disposition", M.State.replay(MCP.Res.changes(esc), s), "0")
    +send : H.Step = result_step(MCP.Mcp.mail.call(34n, s, 5n, "run", J.Json.obj([J.KV{"text", J.Str{"The selected source is ready"}}, J.KV{"conv", J.Str{"conv"}}])))
    check("uncommitted reply attempt still requires fallback", M.State.replay(H.Queue.changes(send), s), "1")
    +committed_reply : List<&2, M.Change> = committed(H.Step.outs_of(send))
    C.Check.str("production mail path emitted a journal header", Nat.show(List.length(&2, M.Change, committed_reply)), "1")
    check("actual run-thread reply is recognized after durable append", M.State.replay(committed_reply, s), "0")
    +quiet : M.State = M.State.replay([M.SettingSet{"notify.all", "off", 4n}, M.SettingSet{"notify.settled", "off", 4n}], base())
    check("quiet notifications do not suppress internal escalation", quiet, "1")
    +quiet_after : M.State = M.State.replay(H.Queue.changes(finish(quiet, M.Completed{})), quiet)
    C.Check.str("completion notifications remain off", M.Setting.get(quiet_after, "notify.settled", ""), "off")
    C.Check.str("all notifications remain off", M.Setting.get(quiet_after, "notify.all", ""), "off")
    +off_person : M.State = M.State.apply(base(), M.SettingSet{"notify.needs", "off", 4n})
    +person : MCP.Res = MCP.Mcp.run.escalate(True{}, off_person, 5n, r, J.Json.obj([J.KV{"to", J.Str{"person"}}, J.KV{"text", J.Str{"Need a decision"}}]))
    check("suppressed person alert cannot silently resolve request", M.State.replay(MCP.Res.changes(person), off_person), "1")
    +person_on : M.State = M.State.apply(base(), M.SettingSet{"notify.needs", "on", 4n})
    +first_person : M.State = M.State.replay(H.Queue.changes(H.Run.escalate(person_on, 5n, "beta", "conv", "person", "First request")), person_on)
    +second_request : M.State = M.State.apply(first_person, request("m2"))
    +suppressed : M.State = M.State.replay(H.Queue.changes(H.Run.escalate(second_request, 6n, "beta", "conv", "person", "Second request")), second_request)
    C.Check.str("rate-suppressed person alert cannot acknowledge new input", M.Setting.get(suppressed, "run.escalated.run", ""), "m1")
    check("rate-suppressed new input still reaches owner", suppressed, "1")
    +recovered : H.Step = H.Run.recover(base(), 20n, Nil{}, H.Step.none())
    C.Check.str("restart surfaces unresolved unadopted run", Nat.show(posts(H.Queue.changes(recovered), "foh")), "1")
    C.Check.str("adopted live run is not duplicated", Nat.show(posts(H.Queue.changes(H.Run.recover(base(), 20n, ["run"], H.Step.none())), "foh")), "0")
    C.Check.str("restart continue off does not wake owner", Nat.show(posts(H.Queue.changes(H.Run.recover(M.State.apply(base(), M.SettingSet{"restart.continue", "off", 4n}), 20n, Nil{}, H.Step.none())), "foh")), "0")
    +room : M.State = M.State.apply(base(), M.MailPosted{"room2", "conv", "bot:other", "room:shared", "room", "", "act", "New request", 11n, 3n})
    C.Check.str("room request changes the pending input token", H.Run.input(room, r), "room2")
    +busy : M.State = M.State.apply(base(), M.TurnChanged{"foh", M.Running{}, 4n})
    +busy_after : M.State = M.State.replay(H.Queue.changes(finish(busy, M.Completed{})), busy)
    C.Check.str("running owner receives escalation through durable ride", Bool.show(String.contains(H.Ride.of(busy_after, "foh"), "Actionable input: m1")), "True")
    C.Check.str("read status cannot resolve by policy", Bool.show(MCN.Continuity.disposed("open")), "False")
