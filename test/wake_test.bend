import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/hub.bend as H
import ../src/core/wake.bend as W
import ../src/core/codec.bend as K
import ../src/core/mcp.bend as MC
import ../src/core/json.bend as J
import ../src/core/subs.bend as SB
import ../src/core/client.bend as U
import ../src/core/bothub.bend as BH

# These tests exercise replay, delivery and the MCP surface, not just parsing.
def messages(cs: List<&2, M.Change>) -> Nat:
  match cs:
    case Nil{}:
      0n
    case M.MessagePosted{th, _, _, _, _} <> t:
      Nat.add(Bool.pick(Nat, String.eq(th, "tb"), 1n, 0n), messages(t))
    case _ <> t:
      messages(t)

def count(st: H.Step) -> Nat:
  messages(H.Queue.changes(st))

def res.cs(r: MC.Res) -> List<&2, M.Change>:
  match r:
    case MC.Res{_, _, H.Step{cs, _}}:
      cs

def res.ok(r: MC.Res) -> Bool:
  match r:
    case MC.Res{o, _, _}:
      o

def args(s: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(s), J.Null{})

def on(+s: M.State, +a: String) -> MC.Res:
  MC.Mcp.wake.on(s, 5n, "tb", args(a))

def round(+c: M.Change) -> Bool:
  String.eq(J.Json.show(K.Change.encode(c)), J.Json.show(K.Change.encode(Maybe.default(&2, M.Change, K.Change.decode(K.Change.encode(c)), M.WakeDropped{"bad", 0n}))))

def posted(cs: List<&2, M.Change>) -> String:
  match cs:
    case Nil{}:
      ""
    case M.MessagePosted{+th, _, _, +text, _} <> t:
      Bool.pick(String, String.eq(th, "tb"), text, posted(t))
    case _ <> t:
      posted(t)

def ci.pending() -> W.PrSeen:
  W.Wake.pr.parse("{\"state\":\"OPEN\",\"statusCheckRollup\":[{\"name\":\"failed\",\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\"},{\"name\":\"build\",\"status\":\"IN_PROGRESS\"}]}")

def ci.finished() -> W.PrSeen:
  W.Wake.pr.parse("{\"state\":\"OPEN\",\"statusCheckRollup\":[{\"name\":\"failed\",\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\"},{\"name\":\"build\",\"status\":\"COMPLETED\",\"conclusion\":\"SUCCESS\"}]}")

def ci.state() -> M.State:
  M.State.replay([M.WakeSet{"wc", "tb", "pr", "owner/repo#7", ["ci", "ci_fail"], False{}, "", 4n}], H.Wake.demo(True{}, ["end"]))

def ci.next() -> H.Step:
  +s = ci.state()
  H.Wake.pr(M.State.replay(H.Queue.changes(H.Wake.pr(s, 9n, "owner/repo#7", ci.pending())), s), 10n, "owner/repo#7", ci.finished())

def sent.go(cs: List<&2, U.Cmd>) -> String:
  match cs:
    case Nil{}:
      ""
    case U.Send{t} <> _:
      t
    case _ <> t:
      sent.go(t)

def sent(a: U.Act) -> String:
  match a:
    case U.Act{_, cs}:
      sent.go(cs)

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("test tick interval is milliseconds", U32.show(W.Wake.tick.ms("1000")), "1000")
    C.Check.str("default tick interval remains one minute", U32.show(W.Wake.tick.ms("60000")), "60000")
    C.Check.str("zero tick interval falls back to one minute", U32.show(W.Wake.tick.ms("0")), "60000")
    C.Check.str("invalid tick interval falls back to one minute", U32.show(W.Wake.tick.ms("bad")), "60000")
    +s : M.State = H.Wake.demo(False{}, ["end", "done", "idle"])
    +st : H.Step = H.Wake.demo.step(s)
    +after : M.State = M.State.replay(H.Queue.changes(st), s)
    C.Check.str("two events one message; bot without a project delivered", Nat.show(count(st)), "1")
    C.Check.str("same terminal event in a different step is not repeated", Nat.show(H.Wake.demo.partial()), "0")
    C.Check.str("one wake per repeated thread event", Nat.show(H.Wake.demo.twice()), "0")
    C.Check.str("once drops both indexes", Nat.show(H.Wake.demo.dropped()), "0")
    C.Check.str("message names events, last reply, note and cancel", Bool.show(Bool.and(String.contains(posted(H.Queue.changes(st)), "end, done, idle"), Bool.and(String.contains(posted(H.Queue.changes(st)), "DRC fixed"), Bool.and(String.contains(posted(H.Queue.changes(st)), "review it"), String.contains(posted(H.Queue.changes(st)), "wake_cancel"))))), "True")
    C.Check.str("the next turn wakes again", Nat.show(count(H.Launch.tell(after, 11n, "t1", H.Step{[M.TurnChanged{"t1", M.Running{}, 10n}, M.TurnChanged{"t1", M.Completed{}, 11n}], Nil{}}))), "1")
    C.Check.str("end fires even when the queue starts another turn in the same step", Nat.show(count(H.Launch.tell(H.Wake.demo(True{}, ["end"]), 9n, "t1", H.Step{[M.TurnChanged{"t1", M.Completed{}, 9n}, M.TurnChanged{"t1", M.Running{}, 9n}], Nil{}}))), "1")
    C.Check.str("idle does not fire when another turn starts", Nat.show(count(H.Launch.tell(H.Wake.demo(True{}, ["idle"]), 9n, "t1", H.Step{[M.TurnChanged{"t1", M.Completed{}, 9n}, M.TurnChanged{"t1", M.Running{}, 9n}], Nil{}}))), "0")
    C.Check.str("two subscriptions for one recipient deliver once each", Nat.show(count(H.Wake.demo.step(M.State.replay([M.WakeSet{"w2", "tb", "thread", "t1", ["done"], True{}, "second", 5n}], s)))), "2")
    C.Check.str("a busy subscriber queues", Nat.show(H.Lr.queued(H.Queue.changes(H.Wake.demo.step(M.State.replay([M.TurnChanged{"tb", M.Running{}, 8n}], s))), "tb")), "1")
    C.Check.str("ask opens at once", Nat.show(count(H.Launch.tell(H.Wake.demo(True{}, ["ask"]), 9n, "t1", H.Step{[M.AskOpened{"q1", "t1", "question", "AskUserQuestion", "which board?", "", 9n}], Nil{}}))), "1")
    C.Check.str("ask event does not depend on its description", Nat.show(count(H.Launch.tell(H.Wake.demo(True{}, ["ask"]), 9n, "t1", H.Step{[M.AskOpened{"q-empty", "t1", "", "", "", "", 9n}], Nil{}}))), "1")
    C.Check.str("failed fires fail and end once", Nat.show(count(H.Launch.tell(H.Wake.demo(True{}, ["fail", "end"]), 9n, "t1", H.Step{[M.TurnChanged{"t1", M.Failed{}, 9n}], Nil{}}))), "1")
    C.Check.str("agent exit after an ended turn still fires fail", Nat.show(count(H.Hub.agent_gone(M.State.replay([M.TurnChanged{"t1", M.Completed{}, 8n}], H.Wake.demo(True{}, ["fail"])), 9n, "t1", 3))), "1")
    C.Check.str("a failed result followed by process exit does not repeat fail", Nat.show(count(H.Hub.agent_gone(M.State.replay([M.TurnChanged{"t1", M.Failed{}, 8n}], H.Wake.demo(False{}, ["fail"])), 9n, "t1", 3))), "0")
    C.Check.str("interrupted ends", Nat.show(count(H.Launch.tell(H.Wake.demo(True{}, ["end"]), 9n, "t1", H.Step{[M.TurnChanged{"t1", M.Interrupted{}, 9n}], Nil{}}))), "1")
    C.Check.str("idle waits for work", Nat.show(count(H.Wake.demo.step(M.State.replay([M.WorkSet{"t1", "bg", "bg\tbuild", 8n}], H.Wake.demo(True{}, ["idle"]))))), "0")
    C.Check.str("reject self", Bool.show(res.ok(on(s, "{\"kind\":\"thread\",\"target\":\"tb\"}"))), "False")
    C.Check.str("reject thread elsewhere", W.Wake.error("tb", "thread", "L~t1", ["end"]), "wake on a thread elsewhere is not supported yet")
    C.Check.str("reject unknown event", Bool.show(res.ok(on(s, "{\"kind\":\"thread\",\"target\":\"t1\",\"events\":[\"merged\"]}"))), "False")
    C.Check.str("reject relative file", Bool.show(res.ok(on(s, "{\"kind\":\"file\",\"target\":\"board\"}"))), "False")
    C.Check.str("canonical PR validates", Bool.show(W.Wake.pr.valid("i2cjak/Backplane#77")), "True")
    C.Check.str("invalid PR cannot reach shell", Bool.show(W.Wake.pr.valid("i2cjak/Backplane#7;echo")), "False")
    C.Check.str("bot must give repo", Bool.show(res.ok(on(s, "{\"kind\":\"pr\",\"target\":\"#7\"}"))), "False")
    C.Check.str("WakeSet codec roundtrip", Bool.show(round(M.WakeSet{"w", "tb", "pr", "owner/repo#7", ["merged", "ci_fail"], False{}, "a\n\t\"b", 23n})), "True")
    C.Check.str("WakeDropped codec roundtrip", Bool.show(round(M.WakeDropped{"w", 23n})), "True")
    C.Check.str("bot tool list includes wake_on", Bool.show(String.contains(BH.Bots.list(J.Num{"1"}, Nil{}), "wake_on")), "True")
    C.Check.str("default thread end", String.join(W.Wake.events(W.Wake.get(M.State.replay(res.cs(on(s, "{\"kind\":\"thread\",\"target\":\"t1\"}")), s), "w5-6")), ","), "end")
    C.Check.str("cancel checks owner", Bool.show(res.ok(MC.Mcp.wake.cancel(s, 8n, "t1", "w1"))), "False")
    C.Check.str("cancel removes subscriber and target index", Nat.show(List.length(&2, String, W.Wake.on(M.State.replay(res.cs(MC.Mcp.wake.cancel(s, 8n, "tb", "w1")), s), "thread", "t1"))), "0")
    C.Check.str("deletion records WakeDropped", Bool.show(String.is_empty(J.Json.get_str(W.Wake.get(M.State.replay(H.Queue.changes(H.Wake.after(s, H.Step{[M.ThreadDeleted{"tb", 10n}], Nil{}})), s), "w1"), "id", ""))), "True")
    +ps : M.State = H.Wake.demo.pr()
    +pr : H.Step = H.Wake.pr(ps, 9n, "owner/repo#7", H.Wake.demo.merged())
    C.Check.str("merged PR plus CI one message", Nat.show(count(pr)), "1")
    C.Check.str("identical PR poll no message", Nat.show(H.Wake.demo.pr.twice()), "0")
    C.Check.str("PR message includes title, commit, CI and files", Bool.show(String.contains(posted(H.Queue.changes(pr)), "Route board (7) MERGED; merge commit abc; CI passed; files: pcb.kicad_pcb")), "True")
    C.Check.str("pending CI with failure is ci_fail only", String.join(W.Wake.pr.events(W.Wake.pr.parse("{\"state\":\"OPEN\",\"statusCheckRollup\":[{\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\"},{\"status\":\"IN_PROGRESS\"}]}")), ","), "ci_fail")
    C.Check.str("CI completion does not repeat the earlier failed check", Bool.show(Bool.and(Nat.is_eq(count(ci.next()), 1n), Bool.and(String.contains(posted(H.Queue.changes(ci.next())), "Events: ci."), Bool.not(String.contains(posted(H.Queue.changes(ci.next())), "ci_fail"))))), "True")
    C.Check.str("bad PR response cannot fire CI", Nat.show(List.length(&2, String, W.Wake.pr.events(W.Wake.pr.parse("not json")))), "0")
    +fs : M.State = M.State.replay([M.WakeSet{"wf", "tb", "file", "/tmp/board", ["changed"], False{}, "", 5n}], s)
    +base : H.Step = H.Wake.file(fs, 6n, "/tmp/board", "0:1:10")
    C.Check.str("file baseline does not wake changed", Nat.show(count(base)), "0")
    +fs1 : M.State = M.State.replay(H.Queue.changes(base), fs)
    +changed : H.Step = H.Wake.file(fs1, 7n, "/tmp/board", "0:2:11")
    C.Check.str("file mtime/size change wakes", Nat.show(count(changed)), "1")
    C.Check.str("same file poll no duplicate", Nat.show(count(H.Wake.file(M.State.replay(H.Queue.changes(changed), fs1), 8n, "/tmp/board", "0:2:11"))), "0")
    C.Check.str("exists fires for present file", Nat.show(count(H.Wake.file(M.State.replay([M.WakeSet{"we", "tb", "file", "/tmp/exists", ["exists"], True{}, "", 5n}], s), 6n, "/tmp/exists", "0:1:10"))), "1")
    C.Check.str("missing file no exists", Nat.show(count(H.Wake.file(M.State.replay([M.WakeSet{"we", "tb", "file", "/tmp/exists", ["exists"], True{}, "", 5n}], s), 6n, "/tmp/exists", "missing"))), "0")
    +ws : M.State = M.State.replay([M.WorkSet{"t1", "watch", H.Watch.line("work1", "watching", "build", "run", "make", "-", 0n), 5n}, M.WakeSet{"ww", "tb", "work", "work1", ["end"], True{}, "", 6n}], s)
    +work : H.Step = H.Watch.end(ws, 9n, "t1", "work1", "exit 0", "built")
    C.Check.str("another thread's watched work wakes subscriber", Nat.show(count(work)), "1")
    C.Check.str("duplicate work end no message", Nat.show(count(H.Watch.end(M.State.replay(H.Queue.changes(work), ws), 10n, "t1", "work1", "exit 0", "built"))), "0")
    C.Check.str("no poll without PR/file subscriptions", Nat.show(List.length(&2, H.Out, H.Step.outs_of(H.Wake.poll(s)))), "0")
    C.Check.str("PR target polling deduplicated", Nat.show(List.length(&2, String, W.Wake.targets(M.Wake.ids(M.State.replay([M.WakeSet{"wp2", "tb", "pr", "owner/repo#7", ["closed"], True{}, "", 6n}], ps), "wakes.poll"), ps, "pr", Nil{}))), "1")
    C.Check.str("all clients cancel through wake.cancel", Bool.show(String.contains(sent(U.Ui.act(U.Ui.select.k(U.Ui.init(10n), "tb"), "wake-cancel", "w1")), "wake.cancel")), "True")
    C.Check.str("all clients receive waiting row", SB.Subs.word(Maybe.default(&2, SB.SubRow, List.head(&2, SB.SubRow, SB.Subs.wakes(s, "tb")), SB.SubRow{"", False{}, "", "", "", "", False{}, False{}, 0n, Nil{}})), "waiting on")
    C.Check.str("waiting row cancel action", SB.Subs.cancel(Maybe.default(&2, SB.SubRow, List.head(&2, SB.SubRow, SB.Subs.wakes(s, "tb")), SB.SubRow{"", False{}, "", "", "", "", False{}, False{}, 0n, Nil{}})), "wake-cancel")
