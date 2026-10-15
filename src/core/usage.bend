import Base
import ./model.bend as M
import ./json.bend as J

# Usage
# -----
# What Settings > Usage says, the same rows in every client. A thread's
# reading (the setting usage.<thread>, from UsageSet) is how much of its
# model's context window the session holds now: a reading, never a total,
# so readings are listed, not summed. Only Claude reports one; a thread on
# another provider says so ("ctx n/a") instead of showing nothing.

type UseT is Data:
  UseT{id: String, title: String, provider: String, model: String, open: Bool, used: Nat, window: Nat}

# a row: its label, its note, and an action for a Refresh button ("" none)
type URow is Data:
  URow{label: String, note: String, act: String}

# whether a provider reports its context (only Claude's stream does)
def Use.reports(+provider: String) -> Bool:
  String.eq(provider, "claude")

def Use.pct(+used: Nat, +window: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_eq(window, 0n), 0n, Nat.div(Nat.mul(used, 100n), window))

def Use.tokens(+n: Nat) -> String:
  Bool.pick(String, Nat.is_ge(n, 1000000n), Nat.show(Nat.div(n, 1000000n)) ++ "M",
    Bool.pick(String, Nat.is_ge(n, 1000n), Nat.show(Nat.div(n, 1000n)) ++ "k", Nat.show(n)))

def Use.tail.k(has: Bool, +provider: String, +text: String) -> String:
  match has:
    case True{}:
      text
    case False{}:
      Bool.pick(String, Use.reports(provider), "", " · ctx n/a")

# the model chip's tail: the reading's text, "ctx n/a" for a provider that
# never reports one, nothing before a reporting provider's first reading
def Use.tail(+provider: String, +used: Nat, +text: String) -> String:
  Use.tail.k(Nat.is_gt(used, 0n), provider, text)

def Use.of.k(t: M.Thread, +v: String) -> UseT:
  match t:
    case M.Thread{+id, _, +ti, _, _, _, _, ar, _, _, _, _, _, _, _, pr, mo, _, _, _, de}:
      UseT{id, Bool.pick(String, String.is_empty(ti), id, ti), pr, mo, Bool.not(Bool.or(ar, de)), M.Usage.used(v), M.Usage.window(v)}

def Use.of(+st: M.State, +t: M.Thread) -> UseT:
  Use.of.k(t, M.Setting.get(st, M.Usage.key(M.Thread.id(t)), ""))

def Use.all(+st: M.State, ts: List<&2, M.Thread>) -> List<&2, UseT>:
  match ts:
    case Nil{}:
      Nil{}
    case t <> r:
      Use.of(st, t) <> Use.all(st, r)

def UseT.open(u: UseT) -> Bool:
  match u:
    case UseT{_, _, _, _, o, _, _}:
      o

def UseT.held(u: UseT) -> Bool:
  match u:
    case UseT{_, _, _, _, o, n, _}:
      Bool.and(o, Nat.is_gt(n, 0n))

def UseT.used(u: UseT) -> Nat:
  match u:
    case UseT{_, _, _, _, _, n, _}:
      n

# fuller first
def UseT.before(a: UseT, b: UseT) -> Bool:
  Nat.is_ge(UseT.used(a), UseT.used(b))

def Use.count(us: List<&2, UseT>, +acc: Nat) -> Nat:
  match us:
    case Nil{}:
      acc
    case _ <> r:
      Use.count(r, Nat.add(acc, 1n))

def Use.held.note(+used: Nat, +window: Nat) -> String:
  Bool.pick(String, Nat.is_eq(window, 0n), Use.tokens(used) ++ " held, window unknown",
    Use.tokens(used) ++ " of " ++ Use.tokens(window) ++ " held (" ++ Nat.show(Use.pct(used, window)) ++ "%)")

def Use.row(u: UseT) -> URow:
  match u:
    case UseT{_, ti, _, +mo, _, n, w}:
      URow{ti, Bool.pick(String, String.is_empty(mo), "default", mo) ++ " · " ++ Use.held.note(n, w), ""}

def Use.rows.t(us: List<&2, UseT>) -> List<&2, URow>:
  match us:
    case Nil{}:
      Nil{}
    case u <> r:
      Use.row(u) <> Use.rows.t(r)

def Use.summary(+held: Nat, +open: Nat) -> URow:
  URow{"Context now", Nat.show(held) ++ " of " ++ Nat.show(open) ++ " open threads have a reading. Only Claude reports one; others show ctx n/a.", ""}

# the fullest open threads' readings, at most `n`
def Use.top(+n: Nat, us: List<&2, UseT>) -> List<&2, URow>:
  Use.rows.t(List.take(&2, UseT, List.sort(~UseT, ~UseT.before, List.filter(~UseT, ~UseT.held, us)), n))

def Use.totals() -> URow:
  URow{"Tokens and cost", "Not recorded yet. A reading is what a session holds now, not what it has used, so readings are not added up.", ""}

def Use.rows.k(+us: List<&2, UseT>) -> List<&2, URow>:
  Use.summary(Use.count(List.filter(~UseT, ~UseT.held, us), 0n), Use.count(List.filter(~UseT, ~UseT.open, us), 0n)) <> List.append(&2, URow, Use.top(8n, us), [Use.totals()])

# Settings > Usage, model side: a summary, the fullest threads, and what is
# not known
def Use.rows(+st: M.State, ts: List<&2, M.Thread>) -> List<&2, URow>:
  Use.rows.k(Use.all(st, ts))

def URow.label(r: URow) -> String:
  match r:
    case URow{l, _, _}:
      l

def URow.note(r: URow) -> String:
  match r:
    case URow{_, n, _}:
      n

def URow.act(r: URow) -> String:
  match r:
    case URow{_, _, a}:
      a

# Boat
# ----
# Boat's side of Settings > Usage. The account comes from Boat's CLI
# (`boat limits --json --no-update`, read-only), which the hub runs at most
# every Bj.every() seconds while Settings is open, or at once from Refresh
# (not again within Bj.again() seconds), and keeps as a cache: when it last
# tried, when it last got an answer, the error if the last try failed, and
# the last answer, so a failure shows the last known values as stale.
# What Backplane itself started comes from the Boat lead's job status
# (bp-coord/usage/DATA-CONTRACT.md); its ledger is the only one. The
# account's numbers (every sandbox on it) stay apart from Backplane's.
# Money is credit-seconds, $1 = 100,000; a reservation is a job's worst
# case, never a charge. A number Boat did not give shows "?", never 0.

def Bj.every() -> Nat:
  300n

def Bj.again() -> Nat:
  10n

# a number as Boat gave it, "" when absent or null
def Bj.rawd(+o: J.Json, +k: String) -> String:
  J.Json.as_raw(J.Json.get(o, k), "")

def Bj.raw.k(+r: String) -> String:
  Bool.pick(String, String.is_empty(r), "?", r)

# a number as Boat gave it, "?" when absent or null
def Bj.raw(+o: J.Json, +k: String) -> String:
  Bj.raw.k(Bj.rawd(o, k))

def Bj.has(+o: J.Json, +k: String) -> Bool:
  Bool.not(String.is_empty(Bj.rawd(o, k)))

def Bj.nat(+o: J.Json, +k: String) -> Nat:
  J.Json.get_nat(o, k, 0n)

def Bj.pad5.k(+s: String) -> String:
  String.repeat("0", Nat.sub(5n, String.length(s))) ++ s

def Bj.pad5(+s: String) -> String:
  Bool.pick(String, Nat.is_ge(String.length(s), 5n), s, Bj.pad5.k(s))

# credit-seconds as dollars, exact ($0.00158 for 158)
def Bj.usd(+cs: Nat) -> String:
  "$" ++ Nat.show(Nat.div(cs, 100000n)) ++ "." ++ Bj.pad5(Nat.show(Nat.mod(cs, 100000n)))

def Bj.usd.k(known: Bool, +cs: Nat) -> String:
  match known:
    case True{}:
      Bj.usd(cs)
    case False{}:
      "?"

def Bj.usd.of(+o: J.Json, +k: String) -> String:
  Bj.usd.k(Bj.has(o, k), Bj.nat(o, k))

# seconds of compute: minutes under an hour, else hours to a tenth
def Bj.hours(+s: Nat) -> String:
  Bool.pick(String, Nat.is_lt(s, 3600n), Nat.show(Nat.div(s, 60n)) ++ " min",
    Nat.show(Nat.div(s, 3600n)) ++ "." ++ Nat.show(Nat.div(Nat.mod(s, 3600n), 360n)) ++ " h")

def Bj.hours.k(known: Bool, +s: Nat) -> String:
  match known:
    case True{}:
      Bj.hours(s)
    case False{}:
      "?"

def Bj.hours.of(+o: J.Json, +k: String) -> String:
  Bj.hours.k(Bj.has(o, k), Bj.nat(o, k))

def Bj.ago(+now: Nat, +at: Nat) -> String:
  Bool.pick(String, Nat.is_lt(Nat.sub(now, at), 60n), "just now",
    Bool.pick(String, Nat.is_lt(Nat.sub(now, at), 3600n), Nat.show(Nat.div(Nat.sub(now, at), 60n)) ++ " min ago",
      Bool.pick(String, Nat.is_lt(Nat.sub(now, at), 86400n), Nat.show(Nat.div(Nat.sub(now, at), 3600n)) ++ " h ago",
        Nat.show(Nat.div(Nat.sub(now, at), 86400n)) ++ " d ago")))

# The hub's cache
# ---------------

def Bj.parse(+s: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(s), J.Null{})

# an answer worth keeping: an object with the account's limits in it
def Bj.valid(+o: J.Json) -> Bool:
  Bj.has(o, "maxActiveSandboxes")

def Bj.cache.k(ok: Bool, +old: J.Json, nw: J.Json, +now: Nat) -> String:
  match ok:
    case True{}:
      J.Json.show(J.Json.obj([J.KV{"at", J.Num{Nat.show(now)}}, J.KV{"ok_at", J.Num{Nat.show(now)}}, J.KV{"err", J.Str{""}}, J.KV{"limits", nw}]))
    case False{}:
      J.Json.show(J.Json.obj([J.KV{"at", J.Num{Nat.show(now)}}, J.KV{"ok_at", J.Num{Nat.show(Bj.nat(old, "ok_at"))}}, J.KV{"err", J.Str{"Boat's CLI did not answer"}},
        J.KV{"limits", J.Json.get_obj(old, "limits")}]))

# the cache after a try: the CLI's output when it is an answer, else the
# last answer kept, with the error and the try's time
def Bj.cache.next(+old: String, +out: String, +now: Nat) -> String:
  Bj.cache.k(Bj.valid(Bj.parse(out)), Bj.parse(old), Bj.parse(out), now)

# whether to ask Boat again: Refresh (force) waits Bj.again() since the
# last try, an open Settings Bj.every()
def Bj.due(+old: String, force: Bool, +now: Nat) -> Bool:
  Nat.is_ge(Nat.sub(now, Bj.nat(Bj.parse(old), "at")), Bool.pick(Nat, force, Bj.again(), Bj.every()))

# what clients get (info "boat.usage"): the cache and the job status
def Bj.info(+cache: String, +status: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"cache", Bj.parse(cache)}, J.KV{"status", Bj.parse(status)}]))

# Rows
# ----

# how fresh the account's numbers are
def Bj.fresh.k(+err: String, +ok: Nat, +now: Nat) -> String:
  Bool.pick(String, Nat.is_eq(ok, 0n), Bool.pick(String, String.is_empty(err), "", " · " ++ err),
    Bool.pick(String, String.is_empty(err),
      Bool.pick(String, Nat.is_gt(Nat.sub(now, ok), 900n), " · stale, read ", " · read ") ++ Bj.ago(now, ok),
      " · " ++ err ++ "; last read " ++ Bj.ago(now, ok)))

def Bj.fresh(+c: J.Json, +now: Nat) -> String:
  Bj.fresh.k(J.Json.get_str(c, "err", ""), Bj.nat(c, "ok_at"), now)

def Bj.renews(+l: J.Json) -> String:
  Bool.pick(String, String.is_empty(J.Json.get_str(l, "subscriptionCurrentPeriodEnd", "")), "",
    Bool.pick(String, J.Json.get_bool(l, "subscriptionCancelAtPeriodEnd", False{}), " · ends ", " · renews ") ++
      String.take(J.Json.get_str(l, "subscriptionCurrentPeriodEnd", ""), 10n))

def Bj.plan(+l: J.Json) -> String:
  J.Json.get_str(l, "activeSandboxPlanKey", J.Json.get_str(l, "sandboxPlanKey", "?")) ++ " · $" ++ Bj.raw(l, "sandboxPlanDollars") ++ "/month · " ++
    J.Json.get_str(l, "subscriptionStatus", J.Json.get_str(l, "billingStatus", "?")) ++ Bj.renews(l)

def Bj.mine(+s: J.Json) -> String:
  Bool.pick(String, Bj.has(s, "running"), Bj.raw(s, "running") ++ " running" ++
    Bool.pick(String, Nat.is_gt(Bj.nat(s, "orphans"), 0n), ", " ++ Bj.raw(s, "orphans") ++ " NOT DELETED", ""), "?")

def Bj.blocked(+l: J.Json) -> String:
  Bool.pick(String, J.Json.get_bool(l, "canStart", True{}), "", " · can't start now: " ++ J.Json.get_str(l, "startBlockedReason", "no reason given"))

def Bj.win(+o: J.Json, +name: String) -> String:
  Bj.raw(o, "used") ++ "/" ++ Bj.raw(o, "limit") ++ " " ++ name ++ " (" ++ Bj.raw(o, "remaining") ++ " left)"

def Bj.starts(+s: J.Json) -> String:
  Bj.win(J.Json.get_obj(s, "minute"), "this minute") ++ " · " ++ Bj.win(J.Json.get_obj(s, "hour"), "this hour") ++ " · " ++ Bj.win(J.Json.get_obj(s, "day"), "today")

def Bj.size.k(have: Bool, want: Bool, +t: String) -> String:
  match have want:
    case True{} True{}:
      t
    case False{} False{}:
      t
    case _ _:
      ""

def Bj.size(+m: J.Json, want: Bool) -> String:
  Bj.size.k(J.Json.get_bool(m, "available", False{}), want, J.Json.get_str(m, "type", "?"))

def Bj.join(+a: String, +b: String) -> String:
  Bool.pick(String, String.is_empty(b), a, Bool.pick(String, String.is_empty(a), b, a ++ ", " ++ b))

def Bj.sizes(ms: List<&2, J.Json>, +want: Bool, +acc: String) -> String:
  match ms:
    case Nil{}:
      acc
    case m <> t:
      Bj.sizes(t, want, Bj.join(acc, Bj.size(m, want)))

def Bj.sizes.all(+l: J.Json) -> String:
  Bj.sizes(J.Json.elems(J.Json.get_obj(l, "machineTypes")), True{}, "") ++
    Bool.pick(String, String.is_empty(Bj.sizes(J.Json.elems(J.Json.get_obj(l, "machineTypes")), False{}, "")), "",
      " · not offered: " ++ Bj.sizes(J.Json.elems(J.Json.get_obj(l, "machineTypes")), False{}, ""))

def Bj.sizes.row(+l: J.Json) -> String:
  Bj.raw.k(Bj.sizes.all(l))

# the account, as Boat's CLI last said it
def Bj.account(+l: J.Json, +s: J.Json) -> List<&2, URow>:
  [URow{"Boat sandboxes", Bj.raw(l, "activeSandboxes") ++ " of " ++ Bj.raw(l, "maxActiveSandboxes") ++ " active on the account · Backplane's: " ++ Bj.mine(s) ++ Bj.blocked(l), ""},
   URow{"Boat starts", "Rolling: " ++ Bj.starts(J.Json.get_obj(l, "starts")), ""},
   URow{"Boat compute", Bj.hours.of(l, "subscriptionRemainingSeconds") ++ " of " ++ Bj.hours.of(l, "subscriptionQuotaSeconds") ++ " left this period · " ++
     Bj.hours.of(l, "last24hUsageSeconds") ++ " used in the last 24 h", ""},
   URow{"Boat sizes", Bj.sizes.row(l), ""}]

def Bj.account.k(known: Bool, +l: J.Json, +s: J.Json) -> List<&2, URow>:
  match known:
    case True{}:
      Bj.account(l, s)
    case False{}:
      Nil{}

def Bj.plan.row(+c: J.Json, +now: Nat) -> URow:
  URow{"Boat plan", Bool.pick(String, Bj.valid(J.Json.get_obj(c, "limits")), Bj.plan(J.Json.get_obj(c, "limits")), "Not read yet") ++ Bj.fresh(c, now), "usage-refresh"}

# what Backplane's own jobs cost: today's and this month's actual spend,
# and what open jobs hold in reserve
def Bj.spend(+s: J.Json) -> URow:
  URow{"Boat for Backplane", "Today " ++ Bj.usd.of(J.Json.get_obj(s, "today"), "cost_cs") ++
    Bool.pick(String, Bj.has(J.Json.get_obj(s, "month"), "cost_cs"), " · this month " ++ Bj.usd.of(J.Json.get_obj(s, "month"), "cost_cs"), "") ++
    " · " ++ Bj.usd.of(J.Json.get_obj(s, "today"), "reserved_open_cs") ++ " held for open jobs (worst case, not spent)", ""}

def UseT.title(u: UseT) -> String:
  match u:
    case UseT{_, ti, _, _, _, _, _}:
      ti

def Bj.thread.k(r: Map<&2, M.Thread> & M.Thread) -> M.Thread:
  (_, t) = r
  t

def Bj.thread(s: M.State, +id: String) -> M.Thread:
  match s:
    case M.State{_, ts, _, _, _, _, _, _, _, _, _}:
      Bj.thread.k(Map.get(M.Thread, M.Thread.blank(id), ts, id))

def Bj.who(+st: M.State, +th: String) -> String:
  Bool.pick(String, String.is_empty(th), "started by hand", UseT.title(Use.of(st, Bj.thread(st, th))))

# a job worth a row: starting, running, or a sandbox whose delete was never
# verified
def Bj.shown(+s: String) -> Bool:
  Bool.or(Bool.or(String.eq(s, "running"), String.eq(s, "starting")), String.eq(s, "orphan"))

def Bj.job(+st: M.State, +j: J.Json) -> URow:
  URow{Bool.pick(String, String.eq(J.Json.get_str(j, "state", ""), "orphan"), "Boat sandbox NOT deleted", "Boat job " ++ J.Json.get_str(j, "state", "")) ++ " · " ++ J.Json.get_str(j, "size", "?"),
    Bj.who(st, J.Json.get_str(j, "thread", "")) ++ Bool.pick(String, String.is_empty(J.Json.get_str(j, "machine", "")), "", " on " ++ J.Json.get_str(j, "machine", "")) ++
      " · " ++ Bj.raw(j, "runtime_s") ++ " s · reserved " ++ Bj.usd.of(j, "reserved_cs") ++ " (worst case)", ""}

def Bj.jobs.k(keep: Bool, +st: M.State, j: J.Json, rest: List<&2, URow>) -> List<&2, URow>:
  match keep:
    case True{}:
      Bj.job(st, j) <> rest
    case False{}:
      rest

def Bj.jobs(+st: M.State, js: List<&2, J.Json>) -> List<&2, URow>:
  match js:
    case Nil{}:
      Nil{}
    case +j <> t:
      Bj.jobs.k(Bj.shown(J.Json.get_str(j, "state", "")), st, j, Bj.jobs(st, t))

def Bj.mine.rows(known: Bool, +st: M.State, +s: J.Json) -> List<&2, URow>:
  match known:
    case True{}:
      Bj.spend(s) <> Bj.jobs(st, J.Json.elems(J.Json.get_obj(s, "jobs")))
    case False{}:
      [URow{"Boat for Backplane", "No job status yet.", ""}]

def Bj.rows.k(+st: M.State, +c: J.Json, +s: J.Json, +now: Nat) -> List<&2, URow>:
  List.concat(&2, URow, [[Bj.plan.row(c, now)], Bj.account.k(Bj.valid(J.Json.get_obj(c, "limits")), J.Json.get_obj(c, "limits"), s),
    Bj.mine.rows(Bj.has(s, "running"), st, s)])

# Settings > Usage, Boat side, from the info "boat.usage" ("" before the
# hub has answered: one row with Refresh)
def Bj.rows(+st: M.State, +text: String, +now: Nat) -> List<&2, URow>:
  Bj.rows.k(st, J.Json.get_obj(Bj.parse(text), "cache"), J.Json.get_obj(Bj.parse(text), "status"), now)
