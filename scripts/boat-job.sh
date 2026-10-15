#!/bin/bash
# Run one command on a disposable Boat sandbox (boat.dev), from this worktree.
#
#   scripts/boat-job.sh [--size small|default] [--timeout SECS] [--artifact PATH]...
#                       [--exclude GLOB]... [--budget-usd X] [--wait SECS] [--setup-bend|--no-setup-bend] -- CMD...
#   scripts/boat-job.sh sweep      delete sandboxes this tool started whose job is gone
#   scripts/boat-job.sh status [--json] [--refresh]   the ledger and the cached account limits
#
# Agents run it through Backplane: work_run {command: "scripts/boat-job.sh -- scripts/check.sh"}.
# It never takes the local "bend" lock. Admission follows Boat's live limits:
# active sandboxes and the rolling start windows (minute, hour, day), counting
# other clients' starts, our own attempts and jobs still starting; a full slot
# or minute/hour window waits (--wait, default 1 h), a full day refuses. Opt-in: nothing runs unless this
# project's root is listed in $ROOT/enabled (one absolute path per line).
#
# What it does, in order (any failure before create: nothing created):
#   sweep → live limits → admit (fail closed; worst-case reservation against
#   a daily budget, under a ledger lock so parallel jobs can't overspend) →
#   manifest (git ls-files -co --exclude-standard, secrets/logs/build output
#   dropped) → boat new --no-env --no-snapshots --ttl → ledger → push →
#   pinned Bend (version + sha256 from .github/actions/setup-bend) → run,
#   streamed to stdout and to job.log → artifacts (scp) + provenance.json →
#   delete → verify gone → ledger. Delete runs on success, failure and
#   cancel (SIGTERM from work_cancel). A delete it can't verify is written
#   as an orphan and every later job is refused until a sweep removes it.
#
# Exit: the command's own code; 75 refused, 76 setup failed, 77 cleanup
# unverified, 143 cancelled. URLs are never printed or logged.
set -u
umask 077
# bash reads a script as it runs: run from a private copy, so a rebase or an
# edit of this file during a long job can't change what is running
if [ -z "${BOAT_JOB_COPY:-}" ]; then
  c=$(mktemp "${TMPDIR:-/tmp}/boat-job.XXXXXX") && cat "$0" > "$c" || { echo "boat-job: cannot copy itself" >&2; exit 76; }
  BOAT_JOB_COPY=$c exec bash "$c" "$@"
fi
rm -f "$BOAT_JOB_COPY"   # still readable through the open file

BOAT=${BACKPLANE_BOAT:-}
[ -n "$BOAT" ] || BOAT=$(command -v boat 2>/dev/null || true)
[ -n "$BOAT" ] || BOAT="$HOME/.ascii/bin/boat"
ROOT=${BOAT_JOB_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/backplane/boat}
LEDGER="$ROOT/ledger.jsonl"
mkdir -p "$ROOT/jobs" || exit 76

say() { printf 'boat-job: %s\n' "$*" >&2; }
# Boat's frames (JSON lines when not on a terminal) as plain text, URLs dropped
plain() { python3 -u -c '
import json, sys
for l in sys.stdin:
    t = l.strip()
    if t.startswith("{"):
        try: d = json.loads(t)
        except Exception: d = None
        if isinstance(d, dict):
            if isinstance(d.get("data"), str): sys.stdout.write(d["data"])
            elif isinstance(d.get("stdout"), str): sys.stdout.write(d["stdout"] + d.get("stderr", ""))
            sys.stdout.flush(); continue
    sys.stdout.write(l); sys.stdout.flush()
'; }
nourl() { plain | grep --line-buffered -v -i -E 'https?://' || true; }
now() { date -u +%FT%TZ; }
b() { timeout "${BT:-120}" "$BOAT" "$@" --no-update </dev/null; }

# one JSON line appended to the ledger (fields as key=value args)
ledger() {
  python3 - "$LEDGER" "$@" <<'EOF'
import json, sys, time
path, kv = sys.argv[1], sys.argv[2:]
d = {"at": int(time.time()), "day": time.strftime("%Y-%m-%d", time.gmtime())}
for x in kv:
    k, v = x.split("=", 1)
    d[k] = int(v) if v.lstrip("-").isdigit() else v
with open(path, "a") as f:
    f.write(json.dumps(d) + "\n")
EOF
  status_file
}

# fold the ledger: prints "starting_jobs open_reserved_cs spent_today_cs orphans
# our_create_attempts_last_minute _hour _day unresolved" (starting jobs include
# unclear creates not yet reconciled) and,
# with an argument "ids", the created-and-not-ended ids with their owner pid identity
fold() {
  python3 - "$LEDGER" "${1:-}" <<'EOF'
import json, sys, time
path, mode = sys.argv[1], sys.argv[2]
day = time.strftime("%Y-%m-%d", time.gmtime())
jobs = {}; attempts = []
try:
    lines = open(path).read().splitlines()
except FileNotFoundError:
    lines = []
for l in lines:
    try: e = json.loads(l)
    except Exception: continue
    j = jobs.setdefault(e.get("job", ""), {})
    j.setdefault("events", []).append(e)
    for k in ("id", "pid", "pidid", "day"):
        if k in e and k not in j: j[k] = e[k]
    ev = e.get("ev")
    if ev == "reserve": j["done"] = False; j["reserved"] = e.get("reserved", 0); j["size"] = e.get("size"); j["ttl"] = e.get("ttl")
    if ev == "attempt": attempts.append(e.get("at", 0)); j["attempt_at"] = e.get("at", 0)
    if ev in ("ended", "swept"): j["done"] = True; j["cost"] = e.get("cost", 0); j["orphan"] = False
    if ev == "orphan": j["orphan"] = True
    if ev in ("refused", "released"): j["done"] = True; j.setdefault("cost", 0)
    # an unclear create keeps its slot, start and worst-case reservation until reconciled
    if ev == "ambiguous": j["ambig"] = True
    if ev == "unresolved": j["unresolved"] = True
    if ev == "reconciled": j["done"] = True; j["cost"] = e.get("cost", 0); j["ambig"] = False; j["unresolved"] = False
if mode == "known":
    for j in jobs.values():
        if j.get("id"): print(j["id"])
    sys.exit()
if mode == "ambig":
    for k, j in jobs.items():
        if j.get("ambig") and not j.get("done") and not j.get("id"):
            print(k, j.get("size", ""), j.get("ttl", 0), j.get("attempt_at", 0), j.get("reserved", 0), j.get("pid", ""), j.get("pidid", ""), 1 if j.get("unresolved") else 0)
    sys.exit()
if mode == "ids":
    for k, j in jobs.items():
        if j.get("id") and not j.get("done"):
            print(k, j["id"], j.get("pid", ""), j.get("pidid", ""))
    sys.exit()
open_n = sum(1 for j in jobs.values() if not j.get("done") and not j.get("id"))
open_r = sum(int(j.get("reserved", 0)) for j in jobs.values() if not j.get("done"))
spent = sum(int(j.get("cost", 0)) for j in jobs.values() if j.get("done") and j.get("day") == day)
orph = sum(1 for j in jobs.values() if j.get("orphan"))
now = time.time()
am, ah, ad = (sum(1 for a in attempts if now - a < w) for w in (60, 3600, 86400))
unres = sum(1 for j in jobs.values() if j.get("unresolved") and not j.get("done"))
print(open_n, open_r, spent, orph, am, ah, ad, unres)
EOF
}

pid_id() { [ -r "/proc/$1/stat" ] && echo "$(cat /proc/sys/kernel/random/boot_id):$(sed 's/^.*) //' "/proc/$1/stat" | cut -d' ' -f20)"; }

listed() { b list --json | python3 -c 'import json,sys; [print(s["id"]) for s in json.load(sys.stdin)["sandboxes"]]'; }

# Boat's account limits as the Usage settings read them (account.json; no
# network to read it). Written on every live read; an error keeps the last
# good values and says so. Unknown values are null.
account_cache() {
  python3 - "$ROOT/account.json" "$1" <<'EOF'
import json, os, sys, time
path, raw = sys.argv[1], sys.argv[2]
try: old = json.load(open(path))
except Exception: old = {}
now = int(time.time())
def win(x):
    if not isinstance(x, dict) or x.get("limit") is None: return None
    return {"used": x.get("used"), "limit": x.get("limit"), "remaining": x.get("remaining")}
try:
    d = json.loads(raw)
    st = d.get("starts") or {}
    out = {"refreshed_at": now, "source": "boat limits", "error": "",
      "plan": d.get("sandboxPlanKey") or d.get("planName"), "tier": d.get("accessTier"), "status": d.get("billingStatus"),
      "renews_at": d.get("subscriptionCurrentPeriodEnd"), "trial_ends_at": d.get("subscriptionTrialEndsAt") if d.get("billingStatus") == "trialing" else None,
      "can_start": d.get("canStart"), "blocked_reason": d.get("startBlockedReason"),
      "active": {"used": d.get("activeSandboxes"), "limit": d.get("maxActiveSandboxes")},
      "starts": {"unlimited": bool(st.get("unlimited")), "minute": win(st.get("minute")), "hour": win(st.get("hour")), "day": win(st.get("day"))},
      "sizes": {m.get("type"): bool(m.get("available")) for m in d.get("machineTypes") or []} or None,
      "credit": {"remaining_s": d.get("subscriptionRemainingSeconds"), "balance_s": d.get("creditBalanceSeconds"), "used_s": d.get("creditUsedSeconds"),
                 "trial_cap_s": d.get("trialComputeCapSeconds"), "credit_s_per_usd": d.get("creditSecondsPerDollar")}}
    if "activeSandboxes" not in d: raise ValueError("no activeSandboxes")
except Exception as e:
    out = dict(old) if old else {"refreshed_at": None, "source": "boat limits"}
    out["error"] = "Boat limits unreadable"; out["error_at"] = now
tmp = path + ".tmp"; json.dump(out, open(tmp, "w")); os.replace(tmp, path)
EOF
}
limits_live() { local l; l=$(BT=30 b limits --json 2>/dev/null) || { account_cache ""; return 1; }; account_cache "$l"; printf '%s' "$l"; }

# delete one sandbox of ours and check it is gone; 0 when verified
delete_verify() {
  for i in 1 2 3; do
    BT=60 b delete "$1" --yes --json >/dev/null 2>&1
    l=$(listed) || { sleep 3; continue; }
    printf '%s\n' "$l" | grep -qx "$1" || return 0
    sleep 5
  done
  return 1
}

# Unclear creates (a `boat new` whose answer couldn't be read). Each keeps its
# slot, start and worst-case reservation. A sweep, once its runner is gone,
# looks for the sandbox it may have made: exactly one unknown sandbox of its
# size and lifetime made around the attempt is adopted (then swept like any
# of ours). None by the end of its lifetime (+10 min): it can't exist past
# its auto-stop (no snapshots: erased), so the job is closed and charged its
# worst case. More than one still up after that: unresolved, and new creates
# are refused until they are gone. Other sandboxes are never touched.
reconcile() {
  local amb lj known act
  amb=$(fold ambig); [ -n "$amb" ] || return 0
  lj=$(b list --json 2>/dev/null) || { say "sweep: cannot list sandboxes"; return 1; }
  known=$(fold known | tr '\n' ' ')
  printf '%s\n' "$amb" | while read -r job size ttl at reserved pid pidid unres; do
    if [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null && [ "$(pid_id "$pid")" = "$pidid" ]; then continue; fi
    act=$(printf '%s' "$lj" | python3 -c '
import json, sys, time
from datetime import datetime
known, size, ttl, at = set(sys.argv[1].split()), sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
c = []
for s in json.load(sys.stdin)["sandboxes"]:
    if s["id"] in known or s.get("type") != size or int(s.get("ttlSeconds") or -1) != ttl: continue
    try: t = datetime.fromisoformat(s["createdAt"].replace("Z", "+00:00")).timestamp()
    except Exception: continue
    if at - 10 <= t <= at + 300: c.append(s["id"])
past = time.time() > at + ttl + 600
if len(c) == 1: print("ADOPT", c[0])
elif not c: print("EXPIRED" if past else "WAIT")
else: print("UNRESOLVED" if past else "WAIT", len(c))
' "$known" "$size" "$ttl" "$at")
    case $act in
      ADOPT*) ledger ev=created job="$job" id="${act#ADOPT }" adopted=1; say "adopted ${act#ADOPT } for unclear create $job" ;;
      EXPIRED) ledger ev=reconciled job="$job" cost="$reserved" why="no sandbox by the end of its lifetime; charged its worst case" ;;
      UNRESOLVED*) [ "$unres" = 1 ] || { ledger ev=unresolved job="$job" why="${act#UNRESOLVED } look-alike sandboxes still up past its lifetime"; say "unclear create $job unresolved: check boat list"; } ;;
    esac
  done
}

sweep() {
  reconcile || return 1
  ids=$(fold ids) || return 1
  [ -n "$ids" ] || return 0
  l=$(listed) || { say "sweep: cannot list sandboxes"; return 1; }
  printf '%s\n' "$ids" | while read -r job id pid pidid; do
    [ -n "$id" ] || continue
    if [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null && [ "$(pid_id "$pid")" = "$pidid" ]; then continue; fi   # its job still runs
    if printf '%s\n' "$l" | grep -qx "$id"; then
      u=$(BT=30 b usage "$id" --json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(int(d.get("seconds",0))*int(d.get("billingMultiplier",1)))' 2>/dev/null || echo 0)
      if delete_verify "$id"; then ledger ev=swept job="$job" id="$id" cost="$u"; say "swept $id (job $job)"
      else ledger ev=orphan job="$job" id="$id"; say "sweep could not delete $id"; fi
    else
      ledger ev=swept job="$job" id="$id"
    fi
  done
}

status_json() {
  python3 - "$LEDGER" "$ROOT/account.json" <<'EOF2'
import json, sys, time
day = time.strftime("%Y-%m-%d", time.gmtime()); jobs = {}
try: lines = open(sys.argv[1]).read().splitlines()
except FileNotFoundError: lines = []
for l in lines:
    try: e = json.loads(l)
    except Exception: continue
    j = jobs.setdefault(e.get("job", ""), {"job": e.get("job", ""), "state": "starting"})
    ev = e.get("ev")
    for k in ("size", "ttl", "thread", "work", "project", "machine", "cmd", "src", "day"):
        if k in e and k not in j: j[k] = e[k]
    if ev == "reserve": j["reserved_cs"] = e.get("reserved", 0); j["queued_at"] = e["at"]
    elif ev == "created": j["sandbox"] = e.get("id"); j["started_at"] = e["at"]; j["state"] = "running"
    elif ev == "ended": j["ended_at"] = e["at"]; j["cost_cs"] = e.get("cost", 0); j["rc"] = e.get("rc"); j["state"] = "ended"
    elif ev == "swept": j["ended_at"] = e["at"]; j["state"] = "swept"
    elif ev == "orphan": j["state"] = "orphan"; j["sandbox"] = e.get("id", j.get("sandbox"))
    elif ev == "refused": j["state"] = "refused"; j["why"] = e.get("why", ""); j["ended_at"] = e["at"]
    elif ev == "released": j["state"] = "starting"; j["retries"] = j.get("retries", 0) + 1
    elif ev == "ambiguous": j["state"] = "ambiguous"; j["why"] = e.get("why", ""); j["reconcile_by"] = j.get("attempt_at", e["at"]) + int(j.get("ttl", 0)) + 600
    elif ev == "unresolved": j["state"] = "unresolved"; j["why"] = e.get("why", "")
    elif ev == "reconciled": j["state"] = "reconciled"; j["ended_at"] = e["at"]; j["cost_cs"] = e.get("cost", 0); j["why"] = e.get("why", "")
    elif ev == "attempt": j["attempts"] = j.get("attempts", 0) + 1; j["attempt_at"] = e["at"]
now = int(time.time())
for j in jobs.values():
    if "started_at" in j: j["runtime_s"] = j.get("ended_at", now) - j["started_at"]
out = sorted(jobs.values(), key=lambda j: j.get("queued_at", j.get("ended_at", 0)))
today = [j for j in out if j.get("day") == day]
try: account = json.load(open(sys.argv[2]))
except Exception: account = None
print(json.dumps({"rate": {"credit_s_per_usd": 100000, "small": 0.5, "default": 1, "large": 2}, "account": account,
  "ambiguous": sum(1 for j in out if j["state"] in ("ambiguous", "unresolved")),
  "unresolved": sum(1 for j in out if j["state"] == "unresolved"),
  "running": sum(1 for j in out if j["state"] in ("starting", "running")),
  "orphans": sum(1 for j in out if j["state"] == "orphan"),
  "month": {"month": day[:7], "cost_cs": sum(j.get("cost_cs", 0) for j in out if str(j.get("day", "")).startswith(day[:7]))},
  "generated_at": int(time.time()),
  "today": {"day": day, "cost_cs": sum(j.get("cost_cs", 0) for j in today), "reserved_open_cs": sum(j.get("reserved_cs", 0) for j in out if j["state"] in ("starting", "running", "ambiguous", "unresolved"))},
  "jobs": out}))
EOF2
}
# the folded view for the Usage settings, rewritten whole after every ledger line
status_file() { status_json > "$ROOT/status.json.tmp" 2>/dev/null && mv -f "$ROOT/status.json.tmp" "$ROOT/status.json"; }
with_lock() { exec 9>>"$ROOT/ledger.lock"; flock -w 60 9 || { say "ledger busy"; return 1; }; "$@"; local r=$?; flock -u 9; return $r; }

case ${1:-} in
  sweep) with_lock sweep; exit $? ;;
  status)
    [ "${2:-}" = --refresh ] && { limits_live >/dev/null; shift; set -- status --json; }
    if [ "${2:-}" = --json ]; then
      status_json
      exit 0
    fi
    read -r n r s o <<<"$(fold)"
    echo "open jobs: $n, reserved: \$$(python3 -c "print(round($r/100000,4))"), spent today: \$$(python3 -c "print(round($s/100000,4))"), unverified deletes: $o"
    fold ids; exit 0 ;;
esac

SIZE=default TIMEOUT=1800 WAIT=${BOAT_JOB_WAIT:-3600} BUDGET_USD=${BOAT_JOB_BUDGET_USD:-0.50} SETUP_BEND=auto
ARTS=() EXCL=()
while [ $# -gt 0 ]; do
  case $1 in
    --size) SIZE=$2; shift 2 ;;
    --timeout) TIMEOUT=$2; shift 2 ;;
    --artifact) ARTS+=("$2"); shift 2 ;;
    --exclude) EXCL+=("$2"); shift 2 ;;
    --budget-usd) BUDGET_USD=$2; shift 2 ;;
    --wait) WAIT=$2; shift 2 ;;
    --setup-bend) SETUP_BEND=yes; shift ;;
    --no-setup-bend) SETUP_BEND=no; shift ;;
    --) shift; break ;;
    *) say "unknown option $1"; exit 75 ;;
  esac
done
[ $# -gt 0 ] || { say "no command (use -- CMD...)"; exit 75; }
case $SIZE in small) RATE2=1 ;; default) RATE2=2 ;; large) RATE2=4 ;; *) say "size $SIZE is not supported (small, default or large; large only when the job is measured to need it)"; exit 75 ;; esac
case $TIMEOUT$WAIT in ''|*[!0-9]*) say "bad --timeout or --wait"; exit 75 ;; esac
TTL=$(( TIMEOUT + 600 )); [ $TTL -lt 900 ] && TTL=900; [ $TTL -gt 7200 ] && TTL=7200
[ $(( TIMEOUT + 300 )) -le $TTL ] || { say "--timeout too long for the 2 h lifetime"; exit 75; }
RESERVE=$(( TTL * RATE2 / 2 ))                        # credit-seconds, worst case
BUDGET=$(python3 -c "print(int(float('$BUDGET_USD')*100000))") || exit 75

SRC=$(git rev-parse --show-toplevel 2>/dev/null) || { say "run it inside a git worktree"; exit 75; }
grep -qxF "$SRC" "$ROOT/enabled" 2>/dev/null || grep -qxF "$(git -C "$SRC" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')" "$ROOT/enabled" 2>/dev/null \
  || { say "Boat jobs are off for $SRC (add the repo's root to $ROOT/enabled)"; exit 75; }

JOB="j$(date -u +%Y%m%d%H%M%S)-$$"
# who asked: the Backplane work this runs under (its run.sh is an ancestor:
# <home>/work/w-<thread>-<n>/run.sh), read from /proc, nothing signalled
WORK="" q=$PPID
for _ in 1 2 3 4 5 6; do
  [ -n "$q" ] && [ "$q" -gt 1 ] 2>/dev/null || break
  c=$(tr '\0' ' ' < "/proc/$q/cmdline" 2>/dev/null)
  case $c in *"/work/w-"*"/run.sh"*) WORK=$(printf '%s' "$c" | sed -n 's|.*/work/\(w-[^/]*\)/run.sh.*|\1|p'); break ;; esac
  q=$(awk '{print $4}' "/proc/$q/stat" 2>/dev/null)
done
THREAD=${BACKPLANE_THREAD:-$(printf '%s' "$WORK" | sed -n 's/^w-\(t[0-9]*-[0-9]*\)-[0-9]*$/\1/p')}
PROJECT=$(basename "$(git -C "$SRC" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')")
MACHINE=$(hostname 2>/dev/null || echo "")
OUT="$ROOT/jobs/$JOB"; mkdir -p "$OUT/artifacts"
LOG="$OUT/job.log"
echo "job $JOB: logs and artifacts in $OUT"

# admit, under the ledger lock (limits read inside it, so jobs see each other).
# Answers on stdout "<reason>"; status 0 admitted (reservation written),
# 2 wait (first word of the reason: seconds), 1 refused.
admit() {
  sweep
  read -r n r s o am ah ad u <<<"$(fold)"
  [ "$o" = 0 ] || { echo "a sandbox delete was never verified; run scripts/boat-job.sh sweep"; return 1; }
  [ "$u" = 0 ] || { echo "an unclear Boat create is unresolved (sandboxes like it are still up past its lifetime): check boat list, delete it if it is ours, then run scripts/boat-job.sh sweep"; return 1; }
  lim=$(limits_live) || { echo "cannot read Boat limits"; return 1; }
  why=$(printf '%s' "$lim" | python3 -c '
import json, sys
need, size, n, am, ah, ad = int(sys.argv[1]), sys.argv[2], *map(int, sys.argv[3:7])
try: d = json.load(sys.stdin)
except Exception: print("NO Boat limits unreadable"); sys.exit()
try:
    act, mx, can = int(d["activeSandboxes"]), int(d["maxActiveSandboxes"]), d["canStart"]
    left = [int(d["subscriptionRemainingSeconds"]), int(d["creditBalanceSeconds"])]
    if d.get("trialComputeCapSeconds") is not None: left.append(int(d["trialComputeCapSeconds"]) - int(d["creditUsedSeconds"]))
    types = {m["type"]: m["available"] for m in d["machineTypes"]}
    st = d["starts"]
except Exception: print("NO Boat limits missing a field"); sys.exit()
if not types.get(size): print(f"NO size {size} not available on this account"); sys.exit()
if min(left) < need: print("NO not enough Boat compute left"); sys.exit()
if not can:
    why = str(d.get("startBlockedReason") or "Boat says no new sandboxes now")
    print(("WAIT 60 " if any(w in why.lower() for w in ("rate", "limit", "too many")) else "NO ") + why); sys.exit()
if act + n >= mx: print(f"WAIT 15 {act} active + {n} starting of {mx}"); sys.exit()
if not st.get("unlimited"):
    for w, mine, pause in (("minute", am, 20), ("hour", ah, 120), ("day", ad, 0)):
        x = st.get(w)
        try: rem, lim = int(x["remaining"]), int(x["limit"])
        except Exception: print(f"NO Boat start limit ({w}) unreadable"); sys.exit()
        # the stricter of Boat (sees every client) and our own record (sees our
        # starts at once), less the jobs of ours already admitted and starting
        if min(rem, lim - mine) - n <= 0:
            print((f"WAIT {pause} " if pause else "NO ") + f"start limit per {w}: {lim - rem} of {lim} used (Backplane {mine}), {n} starting"); sys.exit()
print("OK")
' "$RESERVE" "$SIZE" "$n" "$am" "$ah" "$ad")
  case $why in
    OK) ;;
    WAIT*) echo "${why#WAIT }"; return 2 ;;
    *) echo "${why#NO }"; return 1 ;;
  esac
  [ $(( s + r + RESERVE )) -le "$BUDGET" ] || { echo "daily budget \$$BUDGET_USD would be exceeded (spent+reserved $(( s + r )) cs, this job $RESERVE cs)"; return 1; }
  ledger ev=reserve job="$JOB" size="$SIZE" ttl="$TTL" reserved="$RESERVE" src="$SRC" thread="$THREAD" work="$WORK" project="$PROJECT" machine="$MACHINE" cmd="$*" pid=$$ pidid="$(pid_id $$)"
  echo ok
}
refuse() { FINISHING=1; rm -rf "${STAGE:-}"; say "refused: $1"; ledger ev=refused job="$JOB" why="$1" thread="$THREAD" work="$WORK" project="$PROJECT" machine="$MACHINE" size="$SIZE"; exit 75; }
FINISHING=0 STAGE=""
# wait in line (bounded by --wait) while a slot or a minute/hour start window
# is full; one limits read per pause per job, never faster than 15 s
WAITED=0
admit_wait() {
  local why arc p
  while :; do
    why=$(with_lock admit "$@"); arc=$?
    [ $arc = 0 ] && return 0
    [ $arc = 2 ] || refuse "$why"
    p=${why%% *}; why=${why#* }; [ "$p" -ge 15 ] 2>/dev/null || p=15
    [ $(( WAITED + p )) -le "$WAIT" ] || refuse "still waiting after ${WAITED}s: $why"
    echo "waiting ${p}s: $why"
    sleep "$p" & wait $!; WAITED=$(( WAITED + p ))
  done
}
trap 'say "cancelled while waiting"; exit 143' TERM INT HUP
admit_wait "$@"
[ $WAITED = 0 ] || echo "admitted after ${WAITED}s"

ID="" CANCELLED=0 STAGE="" IN_CREATE=0 BEFORE="" ATTEMPT_AT=0
# after a create whose answer is unclear: the one sandbox it may have made,
# only if exactly one unknown sandbox (not listed before, not in the ledger)
# has this job's size and lifetime and was made since the attempt
adopt() {
  local known; known=$(fold known)
  b list --json 2>/dev/null | python3 -c '
import json, sys
before, known, size, ttl, t0 = set(sys.argv[1].split()), set(sys.argv[2].split()), sys.argv[3], int(sys.argv[4]), int(sys.argv[5])
from datetime import datetime
c = []
for s in json.load(sys.stdin)["sandboxes"]:
    if s["id"] in before or s["id"] in known: continue
    try: at = datetime.fromisoformat(s["createdAt"].replace("Z", "+00:00")).timestamp()
    except Exception: continue
    if s.get("type") == size and int(s.get("ttlSeconds") or -1) == ttl and at >= t0 - 10: c.append(s["id"])
if len(c) == 1: print(c[0])
' "$BEFORE" "$known" "$SIZE" "$TTL" "$ATTEMPT_AT"
}
FINISHING=0
finish() {
  rc=$1
  [ "$FINISHING" = 1 ] && exit "$rc"
  FINISHING=1
  trap '' TERM INT HUP
  if [ -z "$ID" ] && [ "$IN_CREATE" = 1 ]; then
    sleep 5; ID=$(adopt); [ -n "$ID" ] && ledger ev=created job="$JOB" id="$ID" adopted=1 pid=$$ pidid="$(pid_id $$)"
  fi
  if [ -n "$ID" ]; then
    u=$(BT=30 b usage "$ID" --json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(int(d.get("seconds",0))*int(d.get("billingMultiplier",1)))' 2>/dev/null || echo "$RESERVE")
    if delete_verify "$ID"; then ledger ev=ended job="$JOB" id="$ID" cost="$u" rc="$rc"; echo "sandbox $ID deleted (verified); used ${u} credit-s (\$$(python3 -c "print(round($u/100000,5))"))"
    else ledger ev=orphan job="$JOB" id="$ID"; say "COULD NOT VERIFY delete of $ID: later jobs are refused until scripts/boat-job.sh sweep removes it"; rc=77; fi
  else
    ledger ev=ended job="$JOB" cost=0 rc="$rc"
  fi
  rm -rf "$STAGE"
  echo "exit $rc · logs $OUT"
  exit "$rc"
}
trap 'CANCELLED=1; say "cancelled"; finish 143' TERM INT HUP
trap 'r=$?; [ "$FINISHING" = 1 ] || { say "unexpected exit $r: cleaning up"; finish 70; }' EXIT

# manifest: tracked + untracked-not-ignored files, secrets/logs/build output dropped
STAGE=$(mktemp -d); NAME=$(basename "$SRC"); mkdir -p "$STAGE/$NAME"
git -C "$SRC" ls-files -co --exclude-standard -z | python3 -c '
import sys, fnmatch, os
excl = sys.argv[1:]
deny = [".env", ".env.*", "*.pem", "*.key", "*.p12", "*.pfx", "id_rsa*", "id_ed25519*", "id_ecdsa*", "auth.json", "credentials*", "*.keystore", "*.jks", "*.log"]
dirs = ("shots-snap/", "dist/", "build/", "node_modules/", ".claude/", ".backplane/", ".backplane-bend/")
for p in sys.stdin.buffer.read().split(b"\0"):
    if not p: continue
    s = p.decode("utf-8", "surrogateescape"); base = os.path.basename(s)
    if s.startswith(dirs) or any(fnmatch.fnmatch(base, g) for g in deny) or any(fnmatch.fnmatch(s, g) for g in excl): continue
    if s.endswith(".jsonl") and not s.startswith("test/"): continue
    sys.stdout.buffer.write(p + b"\0")
' "${EXCL[@]}" > "$OUT/manifest.z"
(cd "$SRC" && tar --null -T "$OUT/manifest.z" -cf - 2>/dev/null) | tar -xf - -C "$STAGE/$NAME" || { say "staging failed"; finish 76; }
(cd "$STAGE/$NAME" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$OUT/manifest.sha256"
REV=$(git -C "$SRC" rev-parse HEAD); DIRTY=$( [ -n "$(git -C "$SRC" status --porcelain)" ] && echo yes || echo no )
echo "source: $SRC @ $REV (dirty: $DIRTY), $(wc -l < "$OUT/manifest.sha256") files, $(du -sh "$STAGE/$NAME" | cut -f1)"

# the sandbox. Every create request is recorded first (it counts against
# Boat's start windows whatever its answer). Rate-limited: the reservation is
# released and the job backs off (retry-after, else 15·2^n s, at most 5
# tries) and is admitted again. Rejected: refused, no retry. Unclear (a
# timeout, no JSON): never retried, so never a second sandbox; the one it may
# have made is adopted if it can be told apart, else reported.
T0=$(date +%s); TRIES=0
while :; do
  BEFORE=$(listed | tr '\n' ' ') || { ledger ev=released job="$JOB"; refuse "cannot list sandboxes before creating"; }
  ATTEMPT_AT=$(date +%s); ledger ev=attempt job="$JOB" size="$SIZE"
  IN_CREATE=1
  new=$(BT=120 b new --type "$SIZE" --no-env --no-snapshots --ttl "$TTL" --json 2>&1); nrc=$?
  read -r ID CLS RA <<<"$(printf '%s\n' "$new" | python3 -c '
import json, sys, re
rc = int(sys.argv[1]); rate = None; err = None
for l in sys.stdin:
    l = l.strip()
    if not l.startswith("{"): continue
    try: d = json.loads(l)
    except Exception: continue
    for c in (d, d.get("sandbox") or {}):
        v = c.get("id") or c.get("sandboxId")
        if isinstance(v, str) and v.startswith("bx_"): print(v, "OK", 0); sys.exit()
    code, status = str(d.get("code", "")).lower(), d.get("status")
    if status == 429 or "rate" in code or "too_many" in code or "limit" in code:
        ra = d.get("retryAfter", d.get("retry_after", d.get("retryAfterSeconds")))
        try: rate = int(float(ra))
        except Exception: rate = 0
    elif isinstance(status, int) and 400 <= status < 500 and status != 408: err = d.get("error") or code or str(status)
if rate is not None: print("-", "RATE", rate)
elif err is not None and rc != 124: print("-", "REJECT", 0)
else: print("-", "UNCLEAR", 0)
' "$nrc")"
  [ "$CLS" = OK ] && break
  case $CLS in
    RATE)
      ledger ev=released job="$JOB" why=rate-limited; IN_CREATE=0; ID=""
      TRIES=$(( TRIES + 1 )); [ $TRIES -lt 5 ] || refuse "Boat kept answering rate-limited"
      p=$(( 15 << (TRIES - 1) )); [ "${RA:-0}" -gt $p ] 2>/dev/null && p=$RA; [ $p -gt 300 ] && p=300
      [ $(( WAITED + p )) -le "$WAIT" ] || refuse "rate-limited, and the wait would pass --wait"
      echo "Boat rate-limited the create; retrying in ${p}s"
      sleep "$p" & wait $!; WAITED=$(( WAITED + p ))
      admit_wait "$@" ;;
    REJECT)
      IN_CREATE=0; ID=""; ledger ev=released job="$JOB"
      refuse "Boat rejected the create: $(printf '%s' "$new" | nourl | head -c 200)" ;;
    *)
      sleep 5; ID=$(adopt)
      [ -n "$ID" ] && { echo "create answered unclearly; adopted its sandbox $ID"; break; }
      IN_CREATE=0; ID=""
      ledger ev=ambiguous job="$JOB" why="create answered unclearly and no sandbox could be matched"
      say "the create answered unclearly and no matching sandbox appeared; not retrying (no duplicate). Its slot and worst-case budget stay reserved until a sweep reconciles it (at most its lifetime + 10 min)."
      FINISHING=1; rm -rf "$STAGE"; exit 76 ;;
  esac
done
IN_CREATE=0
ledger ev=created job="$JOB" id="$ID" pid=$$ pidid="$(pid_id $$)"
echo "sandbox $ID ($SIZE, ttl ${TTL}s, no account env, no snapshots) in $(( $(date +%s) - T0 ))s"

T1=$(date +%s)
BT=600 b push "$ID" "$STAGE/$NAME" --json >/dev/null 2>"$OUT/push.err" || { say "push failed: $(nourl < "$OUT/push.err" | head -c 300)"; finish 76; }
echo "pushed in $(( $(date +%s) - T1 ))s"

# pinned Bend from the pushed tree's CI setup (only when the tree has one, or asked)
BEND_LINE=""
if [ "$SETUP_BEND" != no ] && [ -f "$SRC/.github/actions/setup-bend/action.yml" ]; then
  read -r BV BSUM <<<"$(python3 - "$SRC/.github/actions/setup-bend/action.yml" <<'EOF'
import re, sys
t = open(sys.argv[1]).read()
v = re.search(r'default:\s*"([0-9.]+)"', t); s = re.search(r'linux-x64;\s*sum=([0-9a-f]{64})', t)
print(v.group(1) if v else "", s.group(1) if s else "")
EOF
)"
  [ -n "$BV" ] && [ -n "$BSUM" ] || { say "cannot read the pinned Bend from setup-bend"; finish 76; }
  BEND_LINE="set -e; n=bend-$BV-linux-x64.tar.gz; t=\$(mktemp -d); curl --proto =https --tlsv1.2 -fsSL -o \$t/\$n https://github.com/bendlang/bend/releases/download/v$BV/\$n; echo '$BSUM  '\$t/\$n | sha256sum -c - >/dev/null; tar -xzf \$t/\$n -C \$t; mkdir -p \$HOME/.bend/bin; mv \$t/bend/bend2 \$t/bend/guide \$HOME/.bend/; mv \$t/bend/bin/bend \$HOME/.bend/bin/bend; echo bend $BV sha256-verified;"
elif [ "$SETUP_BEND" = yes ]; then say "--setup-bend: no .github/actions/setup-bend/action.yml here"; finish 76; fi
T2=$(date +%s)
BT=600 b exec "$ID" --timeout 600 -- bash -c "${BEND_LINE} cd /home/user/$NAME && git init -q && git add -A && git -c user.name=boat-job -c user.email=boat-job@localhost commit -qm '$REV' && echo tree committed" > "$OUT/setup.log" 2>&1 \
  || { say "setup failed: $(nourl < "$OUT/setup.log" | tail -5)"; finish 76; }
nourl < "$OUT/setup.log"; echo "setup in $(( $(date +%s) - T2 ))s"

# the command, streamed; check.sh asks for a 1 GiB stack, so the hard limit is raised first
CMD=$(printf '%q ' "$@")
REMOTE="cd /home/user/$NAME && export PATH=\$HOME/.bend/bin:\$PATH BEND_NO_TELEMETRY=1 CI=1 && { [ \"\$(ulimit -Hs)\" = unlimited ] || sudo -n prlimit --pid \$\$ --stack=unlimited:unlimited 2>/dev/null || true; } && ulimit -s 1048576 2>/dev/null; echo \"[boat-job] \$(nproc) cpu, \$(free -g | awk '/Mem:/{print \$2}') GiB, stack \$(ulimit -s)\"; if [ -x /usr/bin/time ]; then /usr/bin/time -f '[boat-job] peak RSS %M KiB, wall %e s, exit %x' $CMD; else $CMD; fi"
T3=$(date +%s)
echo "running: $CMD"
BT=$(( TIMEOUT + 120 )) b exec "$ID" --timeout 0 --stream -- bash -c "$REMOTE" 2>&1 | nourl | tee "$LOG"
RC=${PIPESTATUS[0]}
[ "$RC" = 124 ] && echo "[boat-job] timed out after ${TIMEOUT}s" | tee -a "$LOG"
echo "[boat-job] command exit $RC in $(( $(date +%s) - T3 ))s" | tee -a "$LOG"

# artifacts and provenance, before the delete
for a in "${ARTS[@]}"; do
  BT=600 b scp -r "$ID:/home/user/$NAME/$a" "$OUT/artifacts/" >/dev/null 2>&1 && echo "artifact: $a" || echo "artifact missing: $a"
done
(cd "$OUT/artifacts" && find . -type f -print0 | sort -z | xargs -0 -r sha256sum) > "$OUT/artifacts.sha256"
J_JOB=$JOB J_ID=$ID J_SIZE=$SIZE J_TTL=$TTL J_SRC=$SRC J_REV=$REV J_DIRTY=$DIRTY J_BV=${BV:-} J_BSUM=${BSUM:-} J_CMD=$CMD J_RC=$RC J_T3=$T3 J_OUT=$OUT \
python3 -c '
import json, hashlib, os
e = os.environ
m = open(e["J_OUT"] + "/manifest.sha256", "rb").read()
json.dump({"job": e["J_JOB"], "sandbox": e["J_ID"], "size": e["J_SIZE"], "ttl": int(e["J_TTL"]), "source": e["J_SRC"], "revision": e["J_REV"], "dirty": e["J_DIRTY"],
  "manifest_sha256": hashlib.sha256(m).hexdigest(), "manifest_files": m.count(b"\n"), "bend": e["J_BV"] or None, "bend_sha256": e["J_BSUM"] or None,
  "command": e["J_CMD"].strip(), "exit": int(e["J_RC"]), "started": int(e["J_T3"])}, open(e["J_OUT"] + "/provenance.json", "w"), indent=1)'
finish "$RC"
