import Base
import ../src/core/bot.bend as BT
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/hub.bend as H
import ../src/core/mail.bend as ML
import ../src/core/mailbody.bend as MB
import ../src/core/mailrun.bend as R
import ../src/core/mailtriage.bend as T
import ../src/core/maildisposition.bend as D
import ../src/core/mcp.bend as MC
import ../src/core/bothub.bend as BH
import ../src/core/notice.bend as N
import ../src/core/json.bend as J
import ../src/core/wake.bend as W
import ../src/server/mailcontext.bend as CX

def check(label: String, value: Bool) -> IO(Unit):
  C.Check.str(label, Bool.show(value), "True")

def n(label: String, value: Nat, expected: Nat) -> IO(Unit):
  C.Check.str(label, Nat.show(value), Nat.show(expected))

def base() -> M.State:
  M.State.replay([M.ProjectCreated{"p", "P", "/tmp/p", 1n}, M.ProjectCreated{"q", "Q", "/tmp/q", 1n},
    M.ThreadCreated{"foh", "", "Bub", M.Local{}, "", "/tmp/b", "claude", "opus", 1n},
    M.ThreadCreated{"worker", "p", "Worker", M.Local{}, "", "/tmp/p", "claude", "", 1n},
    M.ThreadCreated{"other", "q", "Other project", M.Local{}, "", "/tmp/q", "claude", "", 1n},
    M.ThreadCreated{"bot-thread", "", "Pip", M.Local{}, "", "/tmp/pip", "claude", "", 1n},
    M.BotSet{"b", "Bub", "foh", 0n, "", 1n}, M.BotSet{"pip", "Pip", "bot-thread", 0n, "", 1n},
    M.SettingSet{"uber.bot", "b", 1n}, M.SettingSet{"mail.on", "off", 1n},
    M.SettingSet{"text.provider", "codex", 1n}, M.SettingSet{"text.model", "gpt-6-luna", 1n},
    M.ThreadLaunched{"worker", "foh", True{}, 1n}, M.TurnChanged{"foh", M.Running{}, 2n},
    M.MessagePosted{"foh", "person-1", M.User{}, "Nordic hardware tests stay on hold; UDP address width unresolved", 2n},
    M.MemorySaved{"b", "hold", "pref", "Keep testing on hold", "Nordic", 2n},
    M.MemorySaved{"pip", "private", "pref", "Other bot memory", "", 2n}], M.State.empty())

def body(+id: String, +want: String) -> MB.Body:
  MB.Body{ML.Conv{"c", "Worker status", "pair", ["thread:worker", "bot:b"], "p", Nil{}, 1n, 10n, 1n},
    ML.Mail{id, "c", "thread:worker", "bot:b", "thread", "", want, "status", 6n, 10n}, "Routine FYI: unchanged hold"}

def committed(+s: M.State, +b: MB.Body) -> M.State:
  M.State.replay(H.Mail.pending(String.is_empty(ML.Conv.id(ML.Box.conv(M.State.mail(s), ML.Mail.conv(MB.Body.mail(b))))), b), s)

def routed() -> M.State:
  +b = body("m1", "fyi")
  +s = committed(base(), b)
  M.State.replay(H.Queue.changes(H.Mail.route(s, 10n, b)), s)

def runid(+s: M.State) -> String:
  ML.Box.live(M.State.mail(s), "b", "c")

def running() -> M.State:
  +s = routed()
  M.State.replay([M.SettingSet{"run.pending." ++ runid(s), "", 11n}, M.TurnChanged{runid(s), M.Running{}, 11n}], s)

def posts(cs: List<&2, M.Change>, +th: String) -> Nat:
  match cs:
    case Nil{}: 0n
    case M.MessagePosted{+t, _, _, _, _} <> rest: Nat.add(Bool.pick(Nat, String.eq(t, th), 1n, 0n), posts(rest, th))
    case _ <> rest: posts(rest, th)

def appends(os: List<&2, H.Out>) -> Nat:
  match os:
    case Nil{}: 0n
    case H.MailAppend{_, _, _} <> t: 1n+appends(t)
    case _ <> t: appends(t)

def res_step(r: MC.Res) -> H.Step:
  match r:
    case MC.Res{_, _, st}: st

def res_json(r: MC.Res) -> J.Json:
  match r:
    case MC.Res{_, j, _}: j

def dispose_args(+id: String) -> J.Json:
  J.Json.obj([J.KV{"input", J.Str{id}}, J.KV{"mode", J.Str{"done"}}, J.KV{"reason", J.Str{"known unchanged hold; no new ask"}}])

def run_got(r: Maybe<&2, ML.Run>) -> ML.Run:
  match r:
    case Some{r}: r
    case None{}: ML.Run.empty()

def run(+s: M.State) -> ML.Run:
  run_got(ML.Box.run_of(M.State.mail(s), runid(s)))

def ask_state() -> M.State:
  +s = running()
  M.State.replay([M.AskOpened{"approval-1", "worker", "approval", "flash", "Flash held hardware?", "", 12n},
    M.MailPosted{"m2", "c", "thread:worker", "bot:b", "ask", "approval-1", "act", "Needs real approval", 10n, 10n}], s)

def quiet_checks() -> IO(Unit):
  do IO<Unit>:
    +b : MB.Body = body("m1", "fyi")
    +s : M.State = committed(base(), b)
    +st : H.Step = H.Mail.route(s, 10n, b)
    check("FYI starts private triage even automation off", Bool.not(String.is_empty(runid(routed()))))
    n("FYI no raw original-chat message", posts(H.Queue.changes(st), "foh"), 0n)
    C.Check.str("triage inherits actual configured provider", H.Run.provider(routed(), "b"), "codex")
    C.Check.str("triage inherits configurable cheap text model", H.Run.model(routed(), "b"), "gpt-6-luna")
    +live : M.State = running()
    +r : MC.Res = MC.Mcp.dispose(live, 12n, runid(live), dispose_args("m1"))
    check("routine notice can be durably acknowledged", MC.Res.good(r))
    +after : M.State = M.State.replay(H.Queue.changes(res_step(r)), live)
    C.Check.str("all handled has no next input", J.Json.get_str(res_json(r), "next_input", "bad"), "")
    +ended : H.Step = H.Run.after(after, 13n, H.Step{[M.TurnChanged{runid(live), M.Completed{}, 13n}], Nil{}})
    C.Check.str("quiet run completion marks owner mailbox done", ML.Mark.status(ML.Box.mark_of(M.State.mail(M.State.replay(H.Queue.changes(ended), after)), "b", "c")), "done")
    C.Check.str("quiet completion produces no coordinator wake", H.Ride.of(M.State.replay(H.Queue.changes(ended), after), "foh"), "")
    C.Check.str("held work not authorized by receipt", M.Setting.get(after, "hardware.permission", "none"), "none")

def scope_checks() -> IO(Unit):
  do IO<Unit>:
    +s : M.State = running()
    +th : String = runid(s)
    check("run has owner cross-project coordination scope", MC.Mcp.same_project(s, th, "other"))
    check("ordinary worker remains project-scoped", Bool.not(MC.Mcp.same_project(s, "worker", "other")))
    C.Check.str("full-history identity is original conversation", CX.Context.owner(s, th), "foh")
    C.Check.str("ordinary worker cannot read owner context", CX.Context.owner(s, "worker"), "")
    check("history target spoof rejected", Bool.not(CX.Context.args(J.Json.obj([J.KV{"thread", J.Str{"bot-thread"}}]))))
    check("history query and cursor accepted", CX.Context.args(J.Json.obj([J.KV{"query", J.Str{"UDP"}}, J.KV{"before", J.Num{"22"}}])))
    check("brief contains current owner hold", String.contains(R.Run.brief(s, "b", "c"), "UDP address width unresolved"))
    check("brief contains owner memory", String.contains(R.Run.brief(s, "b", "c"), "Keep testing on hold"))
    check("brief excludes other bot memory", Bool.not(String.contains(R.Run.brief(s, "b", "c"), "Other bot memory")))
    check("live run advertises full-history tool", String.contains(J.Json.show(MC.Mcp.tools.for(s, th)), "mail_context"))
    check("private system prompt does not impersonate conversational Bub", String.contains(BH.Bots.prompt(s, th, "/tmp"), "Private coordinator mailroom"))
    check("private system prompt excludes owner's primary-interface persona", Bool.not(String.contains(BH.Bots.prompt(s, th, "/tmp"), "# You are the uberbot")))
    check("worker not given full-history tool", Bool.not(String.contains(J.Json.show(MC.Mcp.tools.for(s, "worker")), "mail_context")))

def escalation_checks() -> IO(Unit):
  do IO<Unit>:
    +s : M.State = running()
    +st : H.Step = H.Run.escalate(s, 12n, "b", "c", "person", "Meaningful completion needs your context")
    +after : M.State = M.State.replay(H.Queue.changes(st), s)
    n("even person escalation has no raw chat row", posts(H.Queue.changes(st), "foh"), 0n)
    C.Check.str("escalation does not alert directly", N.Policy.said(H.Queue.changes(st)), "-")
    check("assessment privately reaches original conversation", String.contains(H.Ride.of(after, "foh"), "Meaningful completion"))
    check("escalation contains source thread link", String.contains(H.Ride.of(after, "foh"), "backplane://thread/worker"))
    check("escalation contains project link", String.contains(H.Ride.of(after, "foh"), "backplane://project/p"))
    check("coordinator must author fresh update", String.contains(H.Ride.of(after, "foh"), "OWN contextual update"))
    n("repeated escalation suppressed durably", List.length(&2, M.Change, H.Queue.changes(H.Run.escalate(after, 13n, "b", "c", "bot", "duplicate"))), 0n)
    n("escalated input no failure fallback", List.length(&2, M.Change, H.Queue.changes(H.Run.after(after, 14n, H.Step{[M.TurnChanged{runid(s), M.Failed{}, 14n}], Nil{}}))), 1n)

def ask_checks() -> IO(Unit):
  do IO<Unit>:
    +s : M.State = ask_state()
    C.Check.str("same-second inputs processed oldest first", D.Disposition.current(s, run(s)), "m1")
    +first : MC.Res = MC.Mcp.dispose(s, 12n, runid(s), dispose_args("m1"))
    +after : M.State = M.State.replay(H.Queue.changes(res_step(first)), s)
    C.Check.str("ack advances to actual ask", J.Json.get_str(res_json(first), "next_input", "bad"), "m2")
    check("open approval cannot be silently disposed", Bool.not(MC.Res.good(MC.Mcp.dispose(after, 13n, runid(s), dispose_args("m2")))))
    +esc : H.Step = H.Run.escalate(after, 14n, "b", "c", "person", "Person must approve actual pending request")
    +delivered : M.State = M.State.replay(H.Queue.changes(esc), after)
    check("real source approval remains open", N.Ask.open(delivered, "worker"))
    n("approval not duplicated into coordinator", List.length(&2, M.Ask, M.Asks.all(delivered)), 1n)
    +open : H.Step = H.Run.after(base(), 20n, H.Step{[M.AskOpened{"a-new", "worker", "approval", "flash", "pending", "", 20n}], Nil{}})
    n("worker ask enters one mail pipeline", appends(H.Step.outs_of(open)), 1n)
    n("worker ask event retained", List.length(&2, M.Ask, M.Asks.all(M.State.replay(H.Queue.changes(open), base()))), 1n)
    C.Check.str("worker source ask alert suppressed", N.Policy.said(N.Policy.ask(s, 20n, "worker", "flash", "pending")), "-")

def failure_checks() -> IO(Unit):
  do IO<Unit>:
    +s : M.State = ask_state()
    +st : H.Step = H.Run.after(s, 30n, H.Step{[M.TurnChanged{runid(s), M.Failed{}, 30n}], Nil{}})
    +after : M.State = M.State.replay(H.Queue.changes(st), s)
    check("failed triage forwards earliest unresolved FYI", Bool.not(String.is_empty(M.Setting.get(after, T.Triage.key("b", "m1"), ""))))
    check("failed triage also forwards later approval", Bool.not(String.is_empty(M.Setting.get(after, T.Triage.key("b", "m2"), ""))))
    check("failure reaches owner with uncertainty explicit", String.contains(H.Ride.of(after, "foh"), "remains unresolved"))
    n("failure forwards no raw chat messages", posts(H.Queue.changes(st), "foh"), 0n)
    check("failure leaves actual approval pending", N.Ask.open(after, "worker"))
    C.Check.str("ended run loses history API authority", CX.Context.owner(after, runid(s)), "")
    +again : H.Step = H.Run.after(after, 31n, H.Step{[M.TurnChanged{runid(s), M.Failed{}, 31n}], Nil{}})
    n("replayed failure does not deliver again", List.length(&2, M.Change, H.Queue.changes(again)), 1n)
    +fallback : H.Step = H.Run.after(running(), 32n, H.Step{[M.TurnChanged{runid(running()), M.Interrupted{}, 32n}, M.ActivityLogged{runid(running()), "fail", "error", "fallback-blocked", "No provider available", 32n}], Nil{}})
    check("exhausted provider fallback is not swallowed", Bool.not(String.is_empty(H.Ride.of(M.State.replay(H.Queue.changes(fallback), running()), "foh"))))

def wake_checks() -> IO(Unit):
  do IO<Unit>:
    +a : J.Json = J.Json.obj([J.KV{"kind", J.Str{"thread"}}, J.KV{"target", J.Str{"worker"}}])
    +covered : MC.Res = MC.Mcp.wake.on(base(), 40n, "foh", a)
    n("launched subscription already covers new wake requests", List.length(&2, M.Change, H.Queue.changes(res_step(covered))), 0n)
    +unreported : M.State = M.State.apply(base(), M.ThreadLaunched{"worker", "foh", False{}, 39n})
    +one : MC.Res = MC.Mcp.wake.on(unreported, 40n, "foh", a)
    +s : M.State = M.State.replay(H.Queue.changes(res_step(one)), unreported)
    +two : MC.Res = MC.Mcp.wake.on(s, 41n, "foh", a)
    n("duplicate subscription reuses existing id", List.length(&2, M.Change, H.Queue.changes(res_step(two))), 0n)
    C.Check.str("duplicate id is stable", J.Json.get_str(res_json(two), "id", ""), J.Json.get_str(res_json(one), "id", "bad"))
    +signal : List<&2, W.WakeSignal> = [W.WakeSignal{"end", "worker:end:42"}]
    +fired : H.Step = H.Wake.thread.fire(M.State.apply(s, M.ThreadLaunched{"worker", "foh", True{}, 42n}), 42n, J.Json.get_str(res_json(one), "id", ""), signal, "Worker ended")
    n("launched report suppresses duplicate wake mail", appends(H.Step.outs_of(fired)), 0n)
    C.Check.str("duplicate wake does not bypass triage", H.Ride.of(M.State.replay(H.Queue.changes(fired), s), "foh"), "")
    +wake : H.Step = H.Wake.send(True{}, base(), 43n, "worker", "foh", "file:artifact:1", "artifact ready")
    n("explicit wake files exactly once", appends(H.Step.outs_of(wake)), 1n)
    C.Check.str("explicit wake cannot directly wake coordinator", H.Ride.of(M.State.replay(H.Queue.changes(wake), base()), "foh"), "")

def room_restart_checks() -> IO(Unit):
  do IO<Unit>:
    +s : M.State = base()
    +room : BT.Room = BT.Room{"coord", "Cross-project coordination", ["b", "pip"], 1n, False{}}
    +post : H.Step = BH.Bots.post.id("room-message", s, 50n, "bot-thread", "Pip", "pip", room, "Meaningful status from other project", 0n)
    n("room post journaled exactly once", appends(H.Step.outs_of(post)), 1n)
    n("room report no original-chat rows", posts(H.Queue.changes(post), "foh"), 0n)
    +conv : ML.Conv = ML.Conv{"room:coord", "Coordination", "room", ["bot:b", "bot:pip"], "q", Nil{}, 1n, 50n, 1n}
    +body : MB.Body = MB.Body{conv, ML.Mail{"room-message", "room:coord", "bot:pip", "room:coord", "room", "coord", "fyi", "status", 6n, 50n}, "Cross-project room status"}
    +committed : M.State = committed(s, body)
    +routed : H.Step = H.Mail.route(committed, 50n, body)
    check("room FYI enters owner triage with automation off", Bool.not(String.is_empty(ML.Box.live(M.State.mail(M.State.replay(H.Queue.changes(routed), committed)), "b", "room:coord"))))
    check("room participant links retained", String.contains(T.Triage.source(conv), "backplane://bot/pip"))
    +workerpost : H.Step = MC.Mcp.send.m(True{}, s, 51n, "worker", "foh", "Need cross-project coordination", "auto")
    n("direct report never becomes source chat message", posts(H.Queue.changes(workerpost), "foh"), 0n)
    n("direct report uses same mailbox", appends(H.Step.outs_of(workerpost)), 1n)
    +live : M.State = running()
    +receipt : MC.Res = MC.Mcp.dispose(live, 52n, runid(live), dispose_args("m1"))
    +acknowledged : M.State = M.State.replay(H.Queue.changes(res_step(receipt)), live)
    +retry : MC.Res = MC.Mcp.dispose(acknowledged, 53n, runid(live), dispose_args("m1"))
    check("receipt replay acknowledged successfully", MC.Res.good(retry))
    n("receipt replay writes nothing", List.length(&2, M.Change, H.Queue.changes(res_step(retry))), 0n)
    +restart : M.State = M.State.apply(live, M.SettingSet{"restart.continue", "on", 53n})
    +recovered : H.Step = H.Run.recover(restart, 54n, Nil{}, H.Step.none())
    +after : M.State = M.State.replay(H.Queue.changes(recovered), restart)
    check("restart forwards unresolved input privately", String.contains(H.Ride.of(after, "foh"), "remains unresolved"))
    n("restart never dumps report in original chat", posts(H.Queue.changes(recovered), "foh"), 0n)
    n("second recovery emits nothing", List.length(&2, M.Change, H.Queue.changes(H.Run.recover(after, 55n, Nil{}, H.Step.none()))), 0n)
    +unknown : H.Step = H.Run.after(live, 56n, H.Step{[M.TurnChanged{runid(live), M.Completed{}, 56n}], Nil{}})
    check("successful final without disposition is escalated", String.contains(H.Ride.of(M.State.replay(H.Queue.changes(unknown), live), "foh"), "not evidence of completion"))
    +notice : MC.Res = BH.Bots.call.scoped(True{}, live, 57n, J.Null{}, runid(live), J.Json.obj([J.KV{"name", J.Str{"notify_person"}}, J.KV{"arguments", J.Json.obj([J.KV{"text", J.Str{"Decision needed"}}, J.KV{"reason", J.Str{"needs_you"}}])}]))
    C.Check.str("notify_person from triage cannot bypass owner", N.Policy.said(H.Queue.changes(res_step(notice))), "-")
    +done : H.Step = H.Run.after(s, 58n, H.Step{[M.TurnChanged{"bot-thread", M.Completed{}, 58n}], Nil{}})
    n("other bot completion is filed for triage", appends(H.Step.outs_of(done)), 1n)
    C.Check.str("other bot source completion is quiet", N.Policy.said(N.Policy.end(s, 58n, "bot-thread", "completed")), "-")
    +kept : H.Step = H.Run.recover(restart, 59n, [runid(live)], H.Step.none())
    n("adopted run not restarted/reported", List.length(&2, M.Change, H.Queue.changes(kept)), 0n)

def event_checks() -> IO(Unit):
  do IO<Unit>:
    +s : M.State = running()
    +first : H.Step = H.Run.escalate.topic(True{}, s, 60n, "b", "c", "bot", "artifact complete", "artifact-v1")
    +one : M.State = M.State.replay(H.Queue.changes(first), s)
    +b : MB.Body = body("m2", "fyi")
    +two : M.State = committed(one, b)
    +duplicate : H.Step = H.Run.escalate.topic(True{}, two, 61n, "b", "c", "bot", "duplicate room report", "artifact-v1")
    +after : M.State = M.State.replay(H.Queue.changes(duplicate), two)
    C.Check.str("same event across routes adds no second private delivery", H.Ride.of(after, "foh"), H.Ride.of(one, "foh"))
    C.Check.str("duplicate correlated input is acknowledged", D.Disposition.current(after, run(s)), "")
    +stale : J.Json = J.Json.obj([J.KV{"to", J.Str{"bot"}}, J.KV{"text", J.Str{"out-of-date assessment"}}, J.KV{"input", J.Str{"m1"}}])
    check("MCP escalation rejects stale input identity", Bool.not(MC.Res.good(MC.Mcp.run.call(True{}, 42n, two, 62n, runid(s), stale))))
    +missing : J.Json = J.Json.obj([J.KV{"to", J.Str{"person"}}, J.KV{"text", J.Str{"missing input"}}])
    check("MCP escalation requires input in coordinator runs", Bool.not(MC.Res.good(MC.Mcp.run.call(True{}, 42n, two, 62n, runid(s), missing))))
    +new_event : H.Step = H.Run.escalate.topic(True{}, two, 63n, "b", "c", "bot", "new version has new decision", "artifact-v2")
    check("changed event version can surface independently", String.contains(H.Ride.of(M.State.replay(H.Queue.changes(new_event), two), "foh"), "new version"))
    +read : H.Step = H.Mail.read(two, 64n, 1, "1", J.Json.obj([J.KV{"bot", J.Str{"b"}}, J.KV{"conv", J.Str{"c"}}]))
    C.Check.str("reading does not consume a pending input", D.Disposition.current(M.State.replay(H.Queue.changes(read), two), run(s)), "m2")
    +off : M.State = M.State.apply(s, M.SettingSet{"restart.continue", "off", 65n})
    C.Check.str("disabled restart continuation does not wake owner", H.Ride.of(M.State.replay(H.Queue.changes(H.Run.recover(off, 66n, Nil{}, H.Step.none())), off), "foh"), "")

def delivery_failure_checks() -> IO(Unit):
  do IO<Unit>:
    +s : M.State = base()
    +failed : H.Step = H.Mail.failure(s, 70n, body("not-filed", "act"), "permission denied opening internal journal")
    +after : M.State = M.State.replay(H.Queue.changes(failed), s)
    check("journal failure reports delivery uncertainty privately", String.contains(H.Ride.of(after, "foh"), "delivery FAILED"))
    n("journal failure never claims a committed body", appends(H.Step.outs_of(failed)), 0n)
    n("journal failure no source message in chat", posts(H.Queue.changes(failed), "foh"), 0n)
    n("same journal failure cannot wake repeatedly", List.length(&2, M.Change, H.Queue.changes(H.Mail.failure(after, 71n, body("not-filed", "act"), "retry failed"))), 0n)
    check("owner keeps assessment context after delivery turn failure", String.contains(BH.Bots.prompt(after, "foh", "/tmp"), "delivery FAILED"))

def context_line(+owner: String, +id: String, +text: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"$", J.Str{"MessagePosted"}}, J.KV{"thread", J.Str{owner}}, J.KV{"msg", J.Str{id}}, J.KV{"role", J.Str{"user"}}, J.KV{"text", J.Str{text}}, J.KV{"at", J.Num{"1"}}]))

def context_many(+n: Nat) -> List<&2, String>:
  match n:
    case 0n: Nil{}
    case 1n+k: context_line("foh", Nat.show(n), "Hardware hold") <> context_many(k)

def context_replay_checks() -> IO(Unit):
  do IO<Unit>:
    +ls : List<&2, String> = [context_line("other-owner", "private", "Hardware other-owner-secret"), context_line("foh", "new", "Hardware new"), "{}", context_line("foh", "old", "Hardware old")]
    +args : J.Json = J.Json.obj([J.KV{"query", J.Str{"HARDWARE"}}])
    +r : J.Json <- CX.Context.read(True{}, "", "foh", args, ls)
    n("full replay history searches case-insensitively without a store", List.length(&2, J.Json, J.Json.elems(J.Json.get_obj(r, "messages"))), 2n)
    check("full replay history cannot cross owner scope", Bool.not(String.contains(J.Json.show(r), "other-owner-secret")))
    +older : J.Json <- CX.Context.read(True{}, "", "foh", J.Json.obj([J.KV{"before", J.Num{"3"}}]), ls)
    check("full replay cursor counts nonmessage log lines", Bool.and(String.contains(J.Json.show(older), "Hardware old"), Bool.not(String.contains(J.Json.show(older), "Hardware new"))))
    +page : J.Json <- CX.Context.read(True{}, "", "foh", J.Json.obj(Nil{}), context_many(22n))
    n("full replay history pages twenty messages", List.length(&2, J.Json, J.Json.elems(J.Json.get_obj(page, "messages"))), 20n)
    n("full replay next cursor is last returned log seq", J.Json.get_nat(page, "next", 0n), 3n)
    +tail : J.Json <- CX.Context.read(True{}, "", "foh", J.Json.obj([J.KV{"before", J.Json.get_obj(page, "next")}]), context_many(22n))
    n("full replay next page has no gap or overlap", List.length(&2, J.Json, J.Json.elems(J.Json.get_obj(tail, "messages"))), 2n)
    +denied : J.Json <- CX.Context.read(False{}, "", "foh", args, ls)
    check("full replay history still fails closed for unauthorized calls", Maybe.is_some(&2, J.Json, J.Json.get(denied, "error")))

def main() -> IO(Unit):
  do IO<Unit>:
    quiet_checks()
    scope_checks()
    escalation_checks()
    ask_checks()
    failure_checks()
    wake_checks()
    room_restart_checks()
    event_checks()
    delivery_failure_checks()
    context_replay_checks()
