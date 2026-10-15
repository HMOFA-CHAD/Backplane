import Base
import ./check.bend as C
import ../src/core/client.bend as U
import ../src/core/model.bend as M
import ../src/core/json.bend as J
import ../src/core/hub.bend as H
import ../src/core/codec.bend as CD
import ../src/core/usage.bend as UZ

# Turn usage as the providers report it (shapes measured 2026-10-15, see
# bp-coord/usage/spec-2.md): Claude's result usage is the turn's own and its
# total_cost_usd the process's running total (result_index 0 starts a
# process); Codex's turn.completed usage is the session's running total,
# kept across resume. A line seen again is not counted twice; a new
# session or process starts again; what a provider does not give is not 0.

def js(+s: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(s), J.Null{})

def claude(+key: String, +idx: String, +cost: String, +i: String, +w: String, +r: String, +o: String) -> J.Json:
  js("{\"type\":\"result\",\"uuid\":\"" ++ key ++ "\",\"result_index\":" ++ idx ++ ",\"total_cost_usd\":" ++ cost ++ ",\"usage\":{\"input_tokens\":" ++ i ++
    ",\"cache_creation_input_tokens\":" ++ w ++ ",\"cache_read_input_tokens\":" ++ r ++ ",\"output_tokens\":" ++ o ++ ",\"output_tokens_details\":{\"thinking_tokens\":0}}}")

def codex(+i: String, +c: String, +o: String) -> J.Json:
  js("{\"type\":\"turn.completed\",\"usage\":{\"input_tokens\":" ++ i ++ ",\"cached_input_tokens\":" ++ c ++ ",\"cache_write_input_tokens\":0,\"output_tokens\":" ++ o ++ ",\"reasoning_output_tokens\":0}}")

def log() -> List<&2, M.Change>:
  [M.ProjectCreated{"p1", "demo", "/tmp/demo", 1n},
   M.ThreadCreated{"t1", "p1", "Claude work", M.Local{}, "", "", "claude", "claude-opus-5-5", 1n},
   M.ThreadCreated{"t2", "p1", "Codex work", M.Local{}, "", "", "codex", "gpt-6.1-sol", 1n},
   M.SessionSet{"t2", "s1", 2n}]

def then(+st: M.State, cs: List<&2, M.Change>) -> M.State:
  M.State.replay(cs, st)

def cl(+st: M.State, +o: J.Json) -> M.State:
  then(st, H.Turn.claude(st, "t1", 1792100000n, o))

def cx(+st: M.State, +o: J.Json) -> M.State:
  then(st, H.Turn.codex(st, "t2", 1792100000n, o))

def count(cs: List<&2, M.Change>) -> String:
  Nat.show(List.length(&2, M.Change, cs))

def round(c: M.Change) -> String:
  J.Json.show(CD.Change.encode(Maybe.default(&2, M.Change, CD.Change.decode(CD.Change.encode(c)), M.SettingSet{"", "", 0n})))

def limit(+five: String, +resets: String) -> J.Json:
  js("{\"type\":\"rate_limit_event\",\"rate_limit_info\":{\"status\":\"allowed_warning\",\"unifiedWindows\":{\"five_hour\":{\"utilization\":" ++ five ++
    ",\"resetsAt\":" ++ resets ++ "},\"seven_day\":{\"utilization\":0.55,\"resetsAt\":1792602000}}}}")

def show(rs: List<&2, UZ.URow>) -> String:
  match rs:
    case Nil{}:
      ""
    case +r <> t:
      UZ.URow.label(r) ++ " | " ++ UZ.URow.note(r) ++ "\n" ++ show(t)

def main() -> IO(Unit):
  do IO<Unit>:
    +s0 : M.State = M.State.replay(log(), M.State.empty())
    +s1 : M.State = cl(s0, claude("r1", "0", "0.0007032500000000001", "2", "3481", "535", "3"))
    +s2 : M.State = cl(s1, claude("r2", "1", "0.0008152200000000001", "2", "367", "3687", "3"))
    C.Check.str("claude: a line again counts nothing", count(H.Turn.claude(s2, "t1", 9n, claude("r2", "1", "0.0008152200000000001", "2", "367", "3687", "3"))), "0")
    +s3 : M.State = cl(s2, claude("r3", "0", "1e-4", "5", "10", "0", "1"))
    C.Check.str("claude totals", M.Setting.get(s3, "tok.t.t1", ""), "3/9/4222/3858/7/0/915220/3")
    C.Check.str("claude cost of turn 2 is the rise", M.Setting.get(s2, "tok.basis.t1", ""), "c:815220")
    C.Check.str("claude without a cost: unknown, not 0", J.Json.show(CD.Change.encode(Maybe.default(&2, M.Change, List.head(&2, M.Change,
      H.Turn.claude(s3, "t1", 5n, js("{\"uuid\":\"r9\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}"))), M.SettingSet{"", "", 0n}))),
      "{\"$\":\"TurnUsage\",\"thread\":\"t1\",\"provider\":\"claude\",\"model\":\"claude-opus-5-5\",\"key\":\"r9\",\"input\":1,\"cread\":0,\"cwrite\":0,\"output\":1,\"reasoning\":0,\"cost\":0,\"known\":\"irwo\",\"basis\":\"c:100000\",\"at\":5}")
    +x1 : M.State = cx(s3, codex("14935", "9984", "5"))
    +x2 : M.State = cx(x1, codex("34717", "17152", "10"))
    C.Check.str("codex: a line again counts nothing", count(H.Turn.codex(x2, "t2", 9n, codex("34717", "17152", "10"))), "0")
    +x3 : M.State = cx(then(x2, [M.SessionSet{"t2", "s2", 3n}]), codex("100", "0", "1"))
    C.Check.str("codex totals (session rises, then a new session)", M.Setting.get(x3, "tok.t.t2", ""), "3/17665/17152/0/11/0/0/0")
    C.Check.str("day", M.Setting.get(x3, "tok.d.2026-10-15", ""), "6/17674/21374/3858/18/0/915220/3")
    C.Check.str("month by model", M.Setting.get(x3, "tok.ml.2026-10", ""), "claude|claude-opus-5-5\ncodex|gpt-6.1-sol")
    C.Check.str("project", M.Setting.get(x3, "tok.p.p1|2026-10", ""), "6/17674/21374/3858/18/0/915220/3")
    C.Check.str("since", M.Setting.get(x3, "tok.since", ""), "1792100000")
    C.Check.str("round trip", round(M.TurnUsage{"t", "claude", "m", "k", 1n, 2n, 3n, 4n, 5n, 6n, "irwotc", "c:6", 7n}),
      "{\"$\":\"TurnUsage\",\"thread\":\"t\",\"provider\":\"claude\",\"model\":\"m\",\"key\":\"k\",\"input\":1,\"cread\":2,\"cwrite\":3,\"output\":4,\"reasoning\":5,\"cost\":6,\"known\":\"irwotc\",\"basis\":\"c:6\",\"at\":7}")
    C.Check.str("utc day", M.Tok.day(0n) ++ " " ++ M.Tok.day(951782400n), "1970-01-01 2000-02-29")
    C.Check.str("limits logged", count(H.Lim.claude(x3, 5n, limit("0.18", "1792105200"))), "2")
    +l1 : M.State = then(x3, H.Lim.claude(x3, 5n, limit("0.18", "1792105200")))
    C.Check.str("limits same again: nothing", count(H.Lim.claude(l1, 6n, limit("0.181", "1792105200"))), "0")
    C.Check.str("limits value", M.Setting.get(l1, "limit.claude.five_hour", ""), "180/1792105200/allowed_warning")
    C.Check.str("rows", show(UZ.Tk.rows(l1, U.Ui.threads(l1), U.Ui.projects(l1), 1792101000n)),
      "Claude plan | 5 h: 18% used, resets in 1 h 10 min · 7 d: 55% used, resets in 5 d · allowed_warning (as Claude last said)\n" ++
      "Today (UTC) | 6 turns · 17k in, 21k cache read, 3k cache write · 18 out (0 reasoning) · $0.0009 for 3 of them\n" ++
      "This month | 6 turns · 17k in, 21k cache read, 3k cache write · 18 out (0 reasoning) · $0.0009 for 3 of them\n" ++
      "claude · claude-opus-5-5 this month | 3 turns · 9 in, 4k cache read, 3k cache write · 7 out (0 reasoning) · $0.0009\n" ++
      "codex · gpt-6.1-sol this month | 3 turns · 17k in, 17k cache read, 0 cache write · 11 out (0 reasoning) · cost not reported\n" ++
      "demo this month | 6 turns · 17k in, 21k cache read, 3k cache write · 18 out (0 reasoning) · $0.0009 for 3 of them\n" ++
      "Codex work so far | 3 turns · 17k in, 17k cache read, 0 cache write · 11 out (0 reasoning) · cost not reported\n" ++
      "Claude work so far | 3 turns · 9 in, 4k cache read, 3k cache write · 7 out (0 reasoning) · $0.0009\n" ++
      "Counted since | 2026-10-15 (UTC); earlier turns were not recorded. Costs are Claude's own figures at API prices, not a bill; Codex reports none.\n")
