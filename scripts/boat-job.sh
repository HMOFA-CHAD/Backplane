#!/bin/bash
# Run one command on a disposable Boat sandbox (boat.dev), from this worktree.
#
#   scripts/boat-job.sh [--size small|default] [--timeout SECS] [--artifact PATH]...
#                       [--exclude GLOB]... [--budget-usd X] [--setup-bend|--no-setup-bend] -- CMD...
#   scripts/boat-job.sh sweep      delete sandboxes this tool started whose job is gone
#   scripts/boat-job.sh status     the ledger: open jobs, today's spend
#
# Agents run it through Backplane: work_run {lock: "boat", command: "scripts/boat-job.sh -- scripts/check.sh"}.
# It never takes the local "bend" lock. Opt-in: nothing runs unless this
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
}

# fold the ledger: prints "starting_jobs open_reserved_cs spent_today_cs orphans" and,
# with an argument "ids", the created-and-not-ended ids with their owner pid identity
fold() {
  python3 - "$LEDGER" "${1:-}" <<'EOF'
import json, sys, time
path, mode = sys.argv[1], sys.argv[2]
day = time.strftime("%Y-%m-%d", time.gmtime())
jobs = {}
try:
    lines = open(path).read().splitlines()
except FileNotFoundError:
    lines = []
for l in lines:
    try: e = json.loads(l)
    except Exception: continue
    j = jobs.setdefault(e.get("job", ""), {})
    j.setdefault("events", []).append(e)
    for k in ("id", "pid", "pidid", "reserved", "day"):
        if k in e and k not in j: j[k] = e[k]
    if e.get("ev") in ("ended", "swept"): j["done"] = True; j["cost"] = e.get("cost", 0); j["orphan"] = False
    if e.get("ev") == "orphan": j["orphan"] = True
    if e.get("ev") == "refused": j["done"] = True; j["cost"] = 0
if mode == "ids":
    for k, j in jobs.items():
        if j.get("id") and not j.get("done"):
            print(k, j["id"], j.get("pid", ""), j.get("pidid", ""))
    sys.exit()
open_n = sum(1 for j in jobs.values() if not j.get("done") and not j.get("id"))
open_r = sum(int(j.get("reserved", 0)) for j in jobs.values() if not j.get("done"))
spent = sum(int(j.get("cost", 0)) for j in jobs.values() if j.get("done") and j.get("day") == day)
orph = sum(1 for j in jobs.values() if j.get("orphan"))
print(open_n, open_r, spent, orph)
EOF
}

pid_id() { [ -r "/proc/$1/stat" ] && echo "$(cat /proc/sys/kernel/random/boot_id):$(sed 's/^.*) //' "/proc/$1/stat" | cut -d' ' -f20)"; }

listed() { b list --json | python3 -c 'import json,sys; [print(s["id"]) for s in json.load(sys.stdin)["sandboxes"]]'; }

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

sweep() {
  ids=$(fold ids) || return 1
  [ -n "$ids" ] || return 0
  l=$(listed) || { say "sweep: cannot list sandboxes"; return 1; }
  printf '%s\n' "$ids" | while read -r job id pid pidid; do
    [ -n "$id" ] || continue
    if [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null && [ "$(pid_id "$pid")" = "$pidid" ]; then continue; fi   # its job still runs
    if printf '%s\n' "$l" | grep -qx "$id"; then
      if delete_verify "$id"; then ledger ev=swept job="$job" id="$id"; say "swept $id (job $job)"
      else ledger ev=orphan job="$job" id="$id"; say "sweep could not delete $id"; fi
    else
      ledger ev=swept job="$job" id="$id"
    fi
  done
}

with_lock() { exec 9>>"$ROOT/ledger.lock"; flock -w 60 9 || { say "ledger busy"; return 1; }; "$@"; local r=$?; flock -u 9; return $r; }

case ${1:-} in
  sweep) with_lock sweep; exit $? ;;
  status)
    read -r n r s o <<<"$(fold)"
    echo "open jobs: $n, reserved: \$$(python3 -c "print(round($r/100000,4))"), spent today: \$$(python3 -c "print(round($s/100000,4))"), unverified deletes: $o"
    fold ids; exit 0 ;;
esac

SIZE=default TIMEOUT=1800 BUDGET_USD=${BOAT_JOB_BUDGET_USD:-0.50} SETUP_BEND=auto
ARTS=() EXCL=()
while [ $# -gt 0 ]; do
  case $1 in
    --size) SIZE=$2; shift 2 ;;
    --timeout) TIMEOUT=$2; shift 2 ;;
    --artifact) ARTS+=("$2"); shift 2 ;;
    --exclude) EXCL+=("$2"); shift 2 ;;
    --budget-usd) BUDGET_USD=$2; shift 2 ;;
    --setup-bend) SETUP_BEND=yes; shift ;;
    --no-setup-bend) SETUP_BEND=no; shift ;;
    --) shift; break ;;
    *) say "unknown option $1"; exit 75 ;;
  esac
done
[ $# -gt 0 ] || { say "no command (use -- CMD...)"; exit 75; }
case $SIZE in small) RATE2=1 ;; default) RATE2=2 ;; *) say "size $SIZE is not available (small or default)"; exit 75 ;; esac
case $TIMEOUT in ''|*[!0-9]*) say "bad --timeout"; exit 75 ;; esac
TTL=$(( TIMEOUT + 600 )); [ $TTL -lt 900 ] && TTL=900; [ $TTL -gt 7200 ] && TTL=7200
[ $(( TIMEOUT + 300 )) -le $TTL ] || { say "--timeout too long for the 2 h lifetime"; exit 75; }
RESERVE=$(( TTL * RATE2 / 2 ))                        # credit-seconds, worst case
BUDGET=$(python3 -c "print(int(float('$BUDGET_USD')*100000))") || exit 75

SRC=$(git rev-parse --show-toplevel 2>/dev/null) || { say "run it inside a git worktree"; exit 75; }
grep -qxF "$SRC" "$ROOT/enabled" 2>/dev/null || grep -qxF "$(git -C "$SRC" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')" "$ROOT/enabled" 2>/dev/null \
  || { say "Boat jobs are off for $SRC (add the repo's root to $ROOT/enabled)"; exit 75; }

JOB="j$(date -u +%Y%m%d%H%M%S)-$$"
OUT="$ROOT/jobs/$JOB"; mkdir -p "$OUT/artifacts"
LOG="$OUT/job.log"
echo "job $JOB: logs and artifacts in $OUT"

# admit, under the ledger lock (limits read inside it, so two jobs see each other)
admit() {
  sweep
  read -r n r s o <<<"$(fold)"
  [ "$o" = 0 ] || { echo "a sandbox delete was never verified; run scripts/boat-job.sh sweep"; return 1; }
  lim=$(BT=30 b limits --json 2>/dev/null) || { echo "cannot read Boat limits"; return 1; }
  why=$(printf '%s' "$lim" | python3 -c '
import json, sys
need, size, open_n = int(sys.argv[1]), sys.argv[2], int(sys.argv[3])
try: d = json.load(sys.stdin)
except Exception: print("Boat limits unreadable"); sys.exit()
try:
    act, mx, can = int(d["activeSandboxes"]), int(d["maxActiveSandboxes"]), d["canStart"]
    left = [int(d["subscriptionRemainingSeconds"]), int(d["creditBalanceSeconds"])]
    if d.get("trialComputeCapSeconds") is not None: left.append(int(d["trialComputeCapSeconds"]) - int(d["creditUsedSeconds"]))
    types = {m["type"]: m["available"] for m in d["machineTypes"]}
except Exception as e: print("Boat limits missing a field"); sys.exit()
if not can: print("Boat says no new sandboxes now"); sys.exit()
if act + open_n >= mx: print(f"{act} running + {open_n} starting of {mx} allowed"); sys.exit()
if not types.get(size): print(f"size {size} not available on this account"); sys.exit()
if min(left) < need: print("not enough Boat compute left"); sys.exit()
' "$RESERVE" "$SIZE" "$n")
  [ -z "$why" ] || { echo "$why"; return 1; }
  [ $(( s + r + RESERVE )) -le "$BUDGET" ] || { echo "daily budget \$$BUDGET_USD would be exceeded (spent+reserved $(( s + r )) cs, this job $RESERVE cs)"; return 1; }
  ledger ev=reserve job="$JOB" size="$SIZE" ttl="$TTL" reserved="$RESERVE" src="$SRC" thread="${BACKPLANE_THREAD:-}" pid=$$ pidid="$(pid_id $$)"
}
why=$(with_lock admit) || { say "refused: $why"; ledger ev=refused job="$JOB" why="$why"; exit 75; }

ID="" CANCELLED=0 STAGE=""
finish() {
  rc=$1
  trap '' TERM INT HUP
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

# the sandbox
T0=$(date +%s)
new=$(BT=120 b new --type "$SIZE" --no-env --no-snapshots --ttl "$TTL" --json 2>&1)
ID=$(printf '%s\n' "$new" | python3 -c '
import json, sys
for l in sys.stdin:
    l = l.strip()
    if not l.startswith("{"): continue
    try: d = json.loads(l)
    except Exception: continue
    for c in (d, d.get("sandbox") or {}):
        v = c.get("id") or c.get("sandboxId")
        if isinstance(v, str) and v.startswith("bx_"): print(v); sys.exit()
')
if [ -z "$ID" ]; then
  # a create that answered oddly may still have made one: adopt it only if it is the single unknown one
  say "boat new gave no id"; ledger ev=ended job="$JOB" cost=0 rc=76; with_lock sweep; exit 76
fi
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
