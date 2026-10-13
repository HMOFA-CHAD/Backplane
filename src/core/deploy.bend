import Base
import ./json.bend as J
import ./model.bend as M

# Safe deploy and restart (docs/deploy.md; the steps are hub.bend's Deploy.*).
# Restarting is fine: the hub resumes every cut turn. What must not be cut
# is a tool call in flight (a build, an edit) and a build under way (the
# machine-wide lock). A deploy waits as the private setting deploy.wait, one
# JSON line; just before the hub execs into the new build it becomes
# deploy.done, which the new process reads once at start.

def Deploy.wait.key() -> String:
  "deploy.wait"

def Deploy.done.key() -> String:
  "deploy.done"

# after this long the requester is told once what still blocks (seconds)
def Deploy.slow() -> Nat:
  1800n

# the line: who asked (a thread id, "" for the person or a script), the
# note, the staged package ("" when the files are in place), the version
# before, when asked, whether the requester was told it is slow, whether
# the build lock was held at the last look, and (done) the threads cut
def Deploy.line(+by: String, +note: String, +stage: String, +from: String, +since: Nat, noted: Bool, locked: Bool, +cut: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"by", J.Str{by}}, J.KV{"note", J.Str{note}}, J.KV{"stage", J.Str{stage}}, J.KV{"from", J.Str{from}},
    J.KV{"since", J.Str{Nat.show(since)}}, J.KV{"noted", J.Flag{noted}}, J.KV{"locked", J.Flag{locked}}, J.KV{"cut", J.Str{cut}}]))

def Deploy.obj(+line: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(line), J.Null{})

def Deploy.wait(+s: M.State) -> String:
  M.Setting.get(s, "deploy.wait", "")

def Deploy.done(+s: M.State) -> String:
  M.Setting.get(s, "deploy.done", "")

def Deploy.waiting(+s: M.State) -> Bool:
  Bool.not(String.is_empty(Deploy.wait(s)))

def Deploy.by(+line: String) -> String:
  J.Json.get_str(Deploy.obj(line), "by", "")

def Deploy.note(+line: String) -> String:
  J.Json.get_str(Deploy.obj(line), "note", "")

def Deploy.stage(+line: String) -> String:
  J.Json.get_str(Deploy.obj(line), "stage", "")

def Deploy.from(+line: String) -> String:
  J.Json.get_str(Deploy.obj(line), "from", "")

def Deploy.since(+line: String) -> Nat:
  M.Switch.num(J.Json.get_str(Deploy.obj(line), "since", "0"), 0n)

def Deploy.noted(+line: String) -> Bool:
  J.Json.get_bool(Deploy.obj(line), "noted", False{})

def Deploy.locked(+line: String) -> Bool:
  J.Json.get_bool(Deploy.obj(line), "locked", False{})

def Deploy.cut(+line: String) -> String:
  J.Json.get_str(Deploy.obj(line), "cut", "")

# whether a thread id is in a comma-joined list
def Deploy.has(ids: List<&2, String>, +id: String) -> Bool:
  match ids:
    case Nil{}:
      False{}
    case +x <> t:
      Bool.or(String.eq(x, id), Deploy.has(t, id))

def Deploy.in(+line: String, +id: String) -> Bool:
  Deploy.has(String.split(Deploy.cut(line), ','), id)

# Tool calls in flight
# --------------------
# The model does not log a tool call's end, but a running thread whose
# newest entry is the Act of a tool call (past the call, the agent's next
# words or call come after it) is inside one. The requester's own
# deploy_* call does not count. Per thread, never a walk of all entries.

def Deploy.tool(es: List<&2, M.Entry>) -> Bool:
  match es:
    case M.Act{_, _, +tone, +kind, _, _} <> _:
      Bool.and(String.eq(tone, "tool"), Bool.not(String.contains(kind, "deploy_")))
    case _:
      False{}

def Deploy.mark(go: Bool, +id: String, rest: List<&2, String>) -> List<&2, String>:
  match go:
    case True{}:
      id <> rest
    case False{}:
      rest

# the live threads running a turn (tools: only those inside a tool call)
def Deploy.ids(+tools: Bool, ts: List<&2, M.Thread>, +s: M.State) -> List<&2, String>:
  match ts:
    case Nil{}:
      Nil{}
    case M.Thread{+id, _, _, _, _, _, _, ar, _, _, _, _, _, _, _, _, _, _, _, _, de} <> t:
      Deploy.mark(Bool.and(Bool.not(Bool.or(ar, de)), Bool.and(M.State.running.k(M.State.thread.get(s, id)),
        Bool.or(Bool.not(tools), Deploy.tool(M.State.mine(s, id))))), id, Deploy.ids(tools, t, s))

def Deploy.threads(+tools: Bool, +s: M.State) -> List<&2, String>:
  match s:
    case M.State{_, +ts, _, _, _, _, _, _, _, _, _}:
      Deploy.ids(tools, Map.values(&2, M.Thread, ts), s)

# the threads inside a tool call
def Deploy.inflight(+s: M.State) -> List<&2, String>:
  Deploy.threads(True{}, s)

def Deploy.count(+s: M.State) -> Nat:
  List.length(&2, String, Deploy.inflight(s))

# the threads a restart now would cut
def Deploy.running(+s: M.State) -> String:
  String.join(Deploy.threads(False{}, s), ",")

# Words
# -----

def Deploy.calls(+n: Nat) -> String:
  Nat.show(n) ++ Bool.pick(String, Nat.is_eq(n, 1n), " tool call", " tool calls")

# what the restart waits for: n tool calls running, the build lock held
def Deploy.blocking(+n: Nat, +locked: Bool) -> String:
  Bool.pick(String, Nat.is_eq(n, 0n), Bool.pick(String, locked, "waiting for the build lock", "waiting for a safe point"),
    "waiting for " ++ Deploy.calls(n) ++ Bool.pick(String, locked, " and the build lock", ""))

def Deploy.blocking.line(+n: Nat, +locked: Bool) -> String:
  Deploy.blocking(n, locked)

def Deploy.row.k(+line: String, +s: M.State) -> String:
  Bool.pick(String, String.is_empty(line), "", "Restart pending · " ++ Deploy.blocking.line(Deploy.count(s), Deploy.locked(line)))

# the plane's and Settings' line while a deploy waits ("" when none does)
def Deploy.row(+s: M.State) -> String:
  Deploy.row.k(Deploy.wait(s), s)

# who asked, for a note: " by <thread> (note)" or ""
def Deploy.who(+by: String, +note: String) -> String:
  Bool.pick(String, String.is_empty(by), "", " by " ++ by) ++ Bool.pick(String, String.is_empty(note), "", " (" ++ note ++ ")")

# said to the requester once, after 30 minutes
def Deploy.slow.text(+n: Nat, locked: Bool) -> String:
  "[Backplane] Your deploy_restart has waited a long time and still " ++ Deploy.blocking.line(n, locked) ++ ". It restarts as soon as that clears; deploy_cancel stops it."

# said after the restart
def Deploy.after.text(+line: String, +to: String) -> String:
  "Backplane restarted for a deploy" ++ Deploy.who(Deploy.by(line), Deploy.note(line)) ++ ": " ++ Deploy.from(line) ++ " → " ++ to ++ "."

def Deploy.suffix.k(+line: String, +to: String) -> String:
  Bool.pick(String, String.is_empty(line), "", "\n\n" ++ Deploy.after.text(line, to) ++ " Your turn was resumed.")

# appended to the continue message of a turn the restart cut ("" when
# there was no deploy)
def Deploy.suffix(+s: M.State, +to: String) -> String:
  Deploy.suffix.k(Deploy.done(s), to)

# the line again with the noted and locked flags set
def Deploy.with(+line: String, noted: Bool, locked: Bool) -> String:
  Deploy.line(Deploy.by(line), Deploy.note(line), Deploy.stage(line), Deploy.from(line), Deploy.since(line), noted, locked, Deploy.cut(line))

def Deploy.status.k(+line: String, +s: M.State) -> J.Json:
  J.Json.obj([J.KV{"waiting", J.Flag{Bool.not(String.is_empty(line))}}, J.KV{"by", J.Str{Deploy.by(line)}}, J.KV{"note", J.Str{Deploy.note(line)}},
    J.KV{"since", J.Str{Nat.show(Deploy.since(line))}}, J.KV{"inflight", J.Num{Nat.show(Deploy.count(s))}},
    J.KV{"threads", J.Str{String.join(Deploy.inflight(s), ",")}}, J.KV{"buildLock", J.Flag{Deploy.locked(line)}}, J.KV{"text", J.Str{Deploy.row.k(line, s)}}])

# what deploy.status and the deploy_status tool answer
def Deploy.status(+s: M.State) -> J.Json:
  Deploy.status.k(Deploy.wait(s), s)
