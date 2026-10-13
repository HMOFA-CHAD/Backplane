import Base
import ./model.bend as M
import ./json.bend as J
import ./codec.bend as C

# Indexed subscription reads and pure event parsing, shared with the poller.
type WakeSignal is Data:
  WakeSignal{event: String, key: String}

type PrSeen is Data:
  PrSeen{state: String, merged: String, commit: String, ci: String, files: List<&2, String>, number: String, title: String, checks: String, failures: String}

def Wake.tick.ms(+text: String) -> U32:
  +ms = Maybe.default(&2, U32, U32.read(text), 60000)
  Bool.pick(U32, U32.is_eq(ms, 0), 60000, ms)

def Wake.get(s: M.State, +id: String) -> J.Json:
  M.Wake.get(s, id)

def Wake.by(s: M.State, +by: String) -> List<&2, String>:
  M.Wake.ids(s, "wakes.by." ++ by)

def Wake.on(s: M.State, +kind: String, +target: String) -> List<&2, String>:
  M.Wake.ids(s, "wakes.on." ++ kind ++ ":" ++ target)

def Wake.events(o: J.Json) -> List<&2, String>:
  C.Codec.wake.events(J.Json.elems(J.Json.get_obj(o, "events")))

def Wake.defaults(+kind: String) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.eq(kind, "pr"), ["merged", "closed"], [Bool.pick(String, String.eq(kind, "file"), "changed", "end")])

def Wake.allowed(+kind: String) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.eq(kind, "thread"), ["end", "done", "fail", "ask", "idle"],
    Bool.pick(List<&2, String>, String.eq(kind, "work"), ["end"],
      Bool.pick(List<&2, String>, String.eq(kind, "pr"), ["merged", "closed", "ci", "ci_fail"],
        Bool.pick(List<&2, String>, String.eq(kind, "file"), ["exists", "changed"], Nil{}))))

def Wake.valid.events(xs: List<&2, String>, +kind: String) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case h <> t:
      Bool.and(M.Launch.has(Wake.allowed(kind), h), Wake.valid.events(t, kind))

# No shell syntax is accepted as a PR target; the poller also passes arguments literally.
def Wake.repo.char(+c: Char) -> Bool:
  Bool.or(Char.is_alpha(c), Bool.or(Char.is_digit(c), Bool.or(Char.is_eq(c, '-'), Bool.or(Char.is_eq(c, '_'), Char.is_eq(c, '.')))))

def Wake.repo.word(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Bool.and(Wake.repo.char(c), Wake.repo.word(t))

def Wake.digits(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Bool.and(Char.is_digit(c), Wake.digits(t))

def Wake.pr.parts(+target: String) -> List<&2, String>:
  String.split(target, '#')

def Wake.pr.repo(+target: String) -> String:
  Maybe.default(&2, String, List.head(&2, String, Wake.pr.parts(target)), "")

def Wake.pr.num(+target: String) -> String:
  Maybe.default(&2, String, List.head(&2, String, List.drop(&2, String, Wake.pr.parts(target), 1n)), "")

def Wake.repo.valid(xs: List<&2, String>) -> Bool:
  match xs:
    case [+a, +b]:
      Bool.and(Bool.and(Bool.not(String.is_empty(a)), Bool.not(String.is_empty(b))), Bool.and(Wake.repo.word(a), Wake.repo.word(b)))
    case _:
      False{}

def Wake.pr.valid(+target: String) -> Bool:
  Bool.and(Nat.is_eq(List.length(&2, String, Wake.pr.parts(target)), 2n),
    Bool.and(Wake.repo.valid(String.split(Wake.pr.repo(target), '/')), Bool.and(Bool.not(String.is_empty(Wake.pr.num(target))), Bool.and(Wake.digits(Wake.pr.num(target)), Bool.not(String.eq(Wake.pr.num(target), "0"))))))

def Wake.error(+by: String, +kind: String, +target: String, +events: List<&2, String>) -> String:
  Bool.pick(String, Bool.not(M.Launch.has(["thread", "work", "pr", "file"], kind)), "kind must be thread, work, pr or file",
    Bool.pick(String, Bool.or(String.is_empty(target), Bool.or(Nat.is_eq(List.length(&2, String, events), 0n), Bool.not(Wake.valid.events(events, kind)))), "target and valid nonempty events are required",
      Bool.pick(String, Bool.and(String.eq(kind, "thread"), String.contains(target, "~")), "wake on a thread elsewhere is not supported yet",
        Bool.pick(String, Bool.and(String.eq(kind, "thread"), String.eq(target, by)), "a subscriber cannot wake itself",
          Bool.pick(String, Bool.and(String.eq(kind, "file"), Bool.not(String.starts_with(target, "/"))), "file target must be an absolute path",
            Bool.pick(String, Bool.and(String.eq(kind, "pr"), Bool.not(Wake.pr.valid(target))), "PR target must be owner/repo#N; bots must give owner/repo", ""))))))

def Wake.select.k(hit: Bool, h: String, rest: List<&2, String>) -> List<&2, String>:
  match hit:
    case True{}:
      h <> rest
    case False{}:
      rest

def Wake.select(xs: List<&2, String>, +actual: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case +h <> t:
      Wake.select.k(M.Launch.has(actual, h), h, Wake.select(t, actual))

def Wake.fresh(+s: M.State, +id: String, +key: String, +events: List<&2, String>) -> Bool:
  Bool.and(Bool.not(String.is_empty(J.Json.get_str(Wake.get(s, id), "id", ""))), Bool.and(Bool.not(Nat.is_eq(List.length(&2, String, events), 0n)), Bool.not(String.eq(M.Setting.get(s, "wake.seen." ++ id, ""), key))))

def Wake.mark(+id: String, +key: String, once: Bool, +now: Nat) -> List<&2, M.Change>:
  M.SettingSet{"wake.seen." ++ id, key, now} <> Bool.pick(List<&2, M.Change>, once, [M.WakeDropped{id, now}], Nil{})

def Wake.note.raw(+o: J.Json, +text: String, +events: List<&2, String>) -> String:
  "Wake " ++ J.Json.get_str(o, "id", "") ++ ": " ++ text ++ " Events: " ++ String.join(events, ", ") ++ "." ++
    Bool.pick(String, String.is_empty(J.Json.get_str(o, "note", "")), "", " Note: " ++ J.Json.get_str(o, "note", "") ++ ".") ++
    Bool.pick(String, J.Json.get_bool(o, "once", True{}), "", " Cancel with wake_cancel {id: " ++ J.Json.get_str(o, "id", "") ++ "}.")

def Wake.list(ids: List<&2, String>, +s: M.State) -> List<&2, J.Json>:
  match ids:
    case Nil{}:
      Nil{}
    case id <> t:
      Wake.get(s, id) <> Wake.list(t, s)

def Wake.drop(ids: List<&2, String>, +now: Nat) -> List<&2, M.Change>:
  match ids:
    case Nil{}:
      Nil{}
    case id <> t:
      M.WakeDropped{id, now} <> Wake.drop(t, now)

def Wake.target.add(+o: J.Json, +kind: String, +out: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, Bool.and(String.eq(J.Json.get_str(o, "kind", ""), kind), Bool.not(M.Launch.has(out, J.Json.get_str(o, "target", "")))), J.Json.get_str(o, "target", "") <> out, out)

def Wake.targets(ids: List<&2, String>, +s: M.State, +kind: String, out: List<&2, String>) -> List<&2, String>:
  match ids:
    case Nil{}:
      out
    case id <> t:
      Wake.targets(t, s, kind, Wake.target.add(Wake.get(s, id), kind, out))

# CI is pending until every check finishes. An empty rollup is no checks.
def Wake.pr.check.done(+o: J.Json) -> Bool:
  Bool.or(String.eq(J.Json.get_str(o, "status", ""), "COMPLETED"), M.Launch.has(["SUCCESS", "FAILURE", "ERROR"], J.Json.get_str(o, "state", "")))

def Wake.pr.check.fail(+o: J.Json) -> Bool:
  Bool.or(M.Launch.has(["FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE"], J.Json.get_str(o, "conclusion", "")), M.Launch.has(["FAILURE", "ERROR"], J.Json.get_str(o, "state", "")))

def Wake.pr.checks(xs: List<&2, J.Json>, +done: Bool, +fail: Bool) -> String:
  match xs:
    case Nil{}:
      Bool.pick(String, fail, Bool.pick(String, done, "failed", "pending; failed"), Bool.pick(String, done, "passed", "pending"))
    case +h <> t:
      Wake.pr.checks(t, Bool.and(done, Wake.pr.check.done(h)), Bool.or(fail, Wake.pr.check.fail(h)))

def Wake.pr.files(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case h <> t:
      J.Json.get_str(h, "path", "") <> Wake.pr.files(t)

def Wake.pr.events(p: PrSeen) -> List<&2, String>:
  match p:
    case PrSeen{+state, +merged, _, +ci, _, _, _, _, _}:
      Bool.pick(List<&2, String>, M.Launch.has(["OPEN", "CLOSED", "MERGED"], state), List.concat(&2, String, [Bool.pick(List<&2, String>, Bool.or(String.eq(state, "MERGED"), Bool.not(String.is_empty(merged))), ["merged"], Nil{}),
        Bool.pick(List<&2, String>, String.eq(state, "CLOSED"), ["closed"], Nil{}),
        Bool.pick(List<&2, String>, M.Launch.has(["passed", "failed", "no checks"], ci), ["ci"], Nil{}),
        Bool.pick(List<&2, String>, String.contains(ci, "failed"), ["ci_fail"], Nil{})]), Nil{})

def Wake.pr.key(p: PrSeen) -> String:
  match p:
    case PrSeen{state, merged, commit, ci, _, _, _, _, _}:
      state ++ ":" ++ merged ++ ":" ++ commit ++ ":" ++ ci

def Wake.pr.text(+target: String, p: PrSeen) -> String:
  match p:
    case PrSeen{state, _, commit, ci, files, number, title, _, _}:
      "PR " ++ target ++ " " ++ title ++ " (" ++ number ++ ") " ++ state ++ "; merge commit " ++ commit ++ "; CI " ++ ci ++ "; files: " ++ String.join(files, ", ")

# Event-specific signatures avoid re-reporting a merge when CI later changes.
def Wake.pr.event.key(+event: String, p: PrSeen) -> String:
  match p:
    case PrSeen{state, merged, commit, ci, _, _, _, checks, failures}:
      Bool.pick(String, String.eq(event, "merged"), "merged:" ++ merged ++ ":" ++ commit,
        Bool.pick(String, String.eq(event, "closed"), "closed:" ++ state, Bool.pick(String, String.eq(event, "ci_fail"), "ci_fail:" ++ failures, event ++ ":" ++ ci ++ ":" ++ checks)))

def Wake.pr.unseen(xs: List<&2, String>, +s: M.State, +id: String, +p: PrSeen) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case +event <> t:
      Wake.select.k(Bool.not(String.eq(M.Setting.get(s, "wake.seen." ++ id ++ "." ++ event, ""), Wake.pr.event.key(event, p))), event, Wake.pr.unseen(t, s, id, p))

def Wake.pr.mark(xs: List<&2, String>, +id: String, +p: PrSeen, +now: Nat) -> List<&2, M.Change>:
  match xs:
    case Nil{}:
      Nil{}
    case +event <> t:
      M.SettingSet{"wake.seen." ++ id ++ "." ++ event, Wake.pr.event.key(event, p), now} <> Wake.pr.mark(t, id, p, now)

# Wake messages are one paragraph even when a reply or reminder has line breaks.
def Wake.flat(s: String, acc: String) -> String:
  match s:
    case SNil{}:
      String.reverse(acc)
    case SCon{+c, t}:
      Wake.flat(t, SCon{Bool.pick(Char, Bool.or(Char.is_eq(c, '\n'), Bool.or(Char.is_eq(c, '\r'), Char.is_eq(c, '\t'))), ' ', c), acc})

def Wake.note(+o: J.Json, +text: String, +events: List<&2, String>) -> String:
  Wake.flat(Wake.note.raw(o, text, events), "")

def Wake.pr.failures(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case +o <> t:
      Wake.select.k(Wake.pr.check.fail(o), J.Json.show(o), Wake.pr.failures(t))

def Wake.pr.parse.o(+o: J.Json) -> PrSeen:
  PrSeen{J.Json.get_str(o, "state", ""), J.Json.get_str(o, "mergedAt", ""), J.Json.get_str(J.Json.get_obj(o, "mergeCommit"), "oid", ""),
    Bool.pick(String, Nat.is_eq(List.length(&2, J.Json, J.Json.elems(J.Json.get_obj(o, "statusCheckRollup"))), 0n), "no checks", Wake.pr.checks(J.Json.elems(J.Json.get_obj(o, "statusCheckRollup")), True{}, False{})),
    Wake.pr.files(List.take(&2, J.Json, J.Json.elems(J.Json.get_obj(o, "files")), 30n)), J.Json.as_raw(J.Json.get(o, "number"), ""), J.Json.get_str(o, "title", ""), J.Json.show(J.Json.get_obj(o, "statusCheckRollup")), String.join(Wake.pr.failures(J.Json.elems(J.Json.get_obj(o, "statusCheckRollup"))), "|")}

def Wake.pr.parse(json: String) -> PrSeen:
  Wake.pr.parse.o(Maybe.default(&2, J.Json, J.Json.parse(json), J.Null{}))

# Thread events retain separate signatures when one step names several.
def Wake.signals(events: List<&2, String>, +end: String, +ask: String) -> List<&2, WakeSignal>:
  match events:
    case Nil{}:
      Nil{}
    case +event <> t:
      WakeSignal{event, Bool.pick(String, String.eq(event, "ask"), ask, end)} <> Wake.signals(t, end, ask)

def Wake.signal.keep(hit: Bool, h: WakeSignal, rest: List<&2, WakeSignal>) -> List<&2, WakeSignal>:
  match hit:
    case True{}:
      h <> rest
    case False{}:
      rest

def Wake.signal.unseen(xs: List<&2, WakeSignal>, +s: M.State, +id: String, +wanted: List<&2, String>) -> List<&2, WakeSignal>:
  match xs:
    case Nil{}:
      Nil{}
    case WakeSignal{+event, +key} <> t:
      Wake.signal.keep(Bool.and(M.Launch.has(wanted, event), Bool.not(String.eq(M.Setting.get(s, "wake.seen." ++ id ++ "." ++ event, ""), key))), WakeSignal{event, key}, Wake.signal.unseen(t, s, id, wanted))

def Wake.signal.events(xs: List<&2, WakeSignal>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case WakeSignal{event, _} <> t:
      event <> Wake.signal.events(t)

def Wake.signal.keys(xs: List<&2, WakeSignal>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case WakeSignal{event, key} <> t:
      (event ++ ":" ++ key) <> Wake.signal.keys(t)

def Wake.signal.mark(xs: List<&2, WakeSignal>, +id: String, +now: Nat) -> List<&2, M.Change>:
  match xs:
    case Nil{}:
      Nil{}
    case WakeSignal{event, key} <> t:
      M.SettingSet{"wake.seen." ++ id ++ "." ++ event, key, now} <> Wake.signal.mark(t, id, now)
