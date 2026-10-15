#!/bin/bash
# scripts/boat-job.sh against test/tools/boat-fake: lifecycle, cleanup,
# budget, admission and the manifest. No network, no real Boat account.
# Signals go only to process groups this test started (setsid).
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' 0
export BOAT_FAKE_DIR=$T/fake BOAT_JOB_ROOT=$T/root BACKPLANE_BOAT=$here/test/tools/boat-fake
mkdir -p "$BOAT_FAKE_DIR" "$BOAT_JOB_ROOT"
pass=0 failn=0
ok() { if [ "$1" = "$2" ]; then pass=$((pass+1)); else failn=$((failn+1)); echo "FAIL $3: got '$1' want '$2'"; fi; }
limits() { echo "{\"activeSandboxes\":ACTIVE,\"maxActiveSandboxes\":${1:-2},\"canStart\":true,\"subscriptionRemainingSeconds\":${2:-90000},\"creditBalanceSeconds\":2000000,\"trialComputeCapSeconds\":90000,\"creditUsedSeconds\":0,\"starts\":STARTS,\"machineTypes\":[{\"type\":\"small\",\"available\":true},{\"type\":\"default\",\"available\":true},{\"type\":\"large\",\"available\":false}]}" > "$BOAT_FAKE_DIR/limits.json"; }
newcalls() { wc -l < "$BOAT_FAKE_DIR/newcalls" 2>/dev/null || echo 0; }
boxes() { find "$BOAT_FAKE_DIR/boxes" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l; }
ended() { grep -c '"ev": "ended"' "$BOAT_JOB_ROOT/ledger.jsonl" 2>/dev/null || echo 0; }

# a project with a secret, build output and a log that must not travel
P=$T/proj; mkdir -p "$P/build" "$P/src"; git -C "$P" init -q
echo 'echo hello' > "$P/src/a.sh"; echo SECRET=1 > "$P/.env"; echo x > "$P/build/x"; echo l > "$P/run.log"; echo u > "$P/untracked.txt"
printf 'build/\n' > "$P/.gitignore"; git -C "$P" add src .gitignore; git -C "$P" -c user.name=t -c user.email=t@t commit -qm init
cd "$P"; limits
J="$here/scripts/boat-job.sh"

# off unless enabled
"$J" -- true >/dev/null 2>&1; ok $? 75 "off by default"; ok "$(boxes)" 0 "off: nothing created"
echo "$P" > "$BOAT_JOB_ROOT/enabled"

# success: output, artifact, provenance, manifest, cleanup, no URL
out=$("$J" --no-setup-bend --artifact res.txt -- sh -c 'echo https://example.invalid/x; cat src/a.sh > res.txt; ls -a; exit 0' 2>&1); rc=$?
ok $rc 0 "success exit"; ok "$(boxes)" 0 "success: deleted"
jd=$(ls -d "$BOAT_JOB_ROOT"/jobs/* | tail -1)
ok "$(cat "$jd/artifacts/res.txt" 2>/dev/null)" "echo hello" "artifact copied"
ok "$(grep -c 'res.txt' "$jd/artifacts.sha256")" 1 "artifact hashed"
ok "$(python3 -c "import json;print(json.load(open('$jd/provenance.json'))['exit'])")" 0 "provenance exit"
ok "$(grep -cE '\.env|build/x|run\.log' "$jd/manifest.sha256")" 0 "manifest drops secrets/build/logs"
ok "$(grep -c 'untracked.txt' "$jd/manifest.sha256")" 1 "manifest keeps untracked source"
ok "$(cat "$jd"/* <(echo "$out") 2>/dev/null | grep -c 'secret-token')" 0 "Boat's URLs never printed or kept"
grep -q -- "--no-env" "$BOAT_FAKE_DIR/calls" && grep -q -- "--no-snapshots" "$BOAT_FAKE_DIR/calls"; ok $? 0 "safe flags"

# the command's exit code passes through, sandbox still deleted
"$J" --no-setup-bend -- sh -c 'exit 3' >/dev/null 2>&1; ok $? 3 "exit passthrough"; ok "$(boxes)" 0 "failure: deleted"

# the script changed under a running job (a rebase): the job is unaffected
cp "$J" "$T/bj.sh"
( "$T/bj.sh" --no-setup-bend -- sleep 3 >/dev/null 2>&1; echo $? > "$T/edit" ) &
sleep 1; printf 'exit 99\n)( syntax\n' > "$T/bj.sh"; wait
ok "$(cat "$T/edit")" 0 "edit during a run"; ok "$(boxes)" 0 "edit: deleted"

# fail closed: unreadable limits, no compute, budget, unknown size
BOAT_FAKE_FAIL=limits "$J" --no-setup-bend -- true >/dev/null 2>&1; ok $? 75 "limits unreadable"
echo '{"activeSandboxes":ACTIVE}' > "$BOAT_FAKE_DIR/limits.json"; "$J" --no-setup-bend -- true >/dev/null 2>&1; ok $? 75 "limits missing fields"
limits 2 100; "$J" --no-setup-bend -- true >/dev/null 2>&1; ok $? 75 "no compute left"; limits
"$J" --no-setup-bend --budget-usd 0.001 -- true >/dev/null 2>&1; ok $? 75 "over budget"
"$J" --size large -- true >/dev/null 2>&1; ok $? 75 "large refused"
ok "$(boxes)" 0 "refusals created nothing"

# cancel (TERM to the job's own process group, as work_cancel does) → deleted, 143
setsid "$J" --no-setup-bend -- sleep 30 > "$T/c.out" 2>&1 & pg=$!
for i in $(seq 50); do [ "$(boxes)" = 1 ] && grep -q running: "$T/c.out" && break; sleep 0.2; done
ok "$(boxes)" 1 "cancel: running"; sleep 1
[ "$pg" -gt 1 ] && kill -TERM -- "-$pg"; wait $pg; ok $? 143 "cancel exit"; ok "$(boxes)" 0 "cancel: deleted"

# crash (KILL, no trap) → left behind → sweep deletes it; a sandbox not ours is never touched
mkdir -p "$BOAT_FAKE_DIR/boxes/bx_notours/home"
setsid "$J" --no-setup-bend -- sleep 30 > "$T/k.out" 2>&1 & pg=$!
for i in $(seq 50); do [ "$(boxes)" = 2 ] && grep -q running: "$T/k.out" && break; sleep 0.2; done
[ "$pg" -gt 1 ] && kill -KILL -- "-$pg"; wait $pg 2>/dev/null
ok "$(boxes)" 2 "crash: left behind"
"$J" sweep >/dev/null 2>&1; ok $? 0 "sweep"; ok "$(boxes)" 1 "sweep deleted ours only"
ok "$(ls "$BOAT_FAKE_DIR/boxes")" bx_notours "foreign sandbox kept"; rm -rf "$BOAT_FAKE_DIR/boxes/bx_notours"

# a delete that can't be verified → 77, then every job refused until a sweep clears it
BOAT_FAKE_FAIL=delete "$J" --no-setup-bend -- true >/dev/null 2>&1; ok $? 77 "unverified delete"
BOAT_FAKE_FAIL=delete "$J" --no-setup-bend -- true >/dev/null 2>&1; ok $? 75 "blocked while the orphan can't be deleted"
"$J" sweep >/dev/null 2>&1; ok "$(boxes)" 0 "sweep removed orphan"
"$J" --no-setup-bend -- true >/dev/null 2>&1; ok $? 0 "unblocked after sweep"

# two jobs at once with budget for one: exactly one admitted
for i in 1 2; do ( "$J" --no-setup-bend --timeout 300 --budget-usd 0.015 -- sleep 2 >/dev/null 2>&1; echo $? > "$T/par$i" ) & done; wait
ok "$(sort "$T/par1" "$T/par2" | tr '\n' ' ')" "0 75 " "budget race: one admitted"
# two jobs at once with one slot and no waiting: exactly one admitted
limits 1
for i in 1 2; do ( "$J" --no-setup-bend --wait 0 -- sleep 2 >/dev/null 2>&1; echo $? > "$T/slot$i" ) & done; wait
ok "$(sort "$T/slot1" "$T/slot2" | tr '\n' ' ')" "0 75 " "slot race: one admitted"
# three jobs on two slots, waiting: all succeed, never more than two sandboxes at once
limits 2; : > "$T/peak"
( for i in $(seq 200); do boxes >> "$T/peak"; sleep 0.1; done ) & mon=$!
for i in 1 2 3; do ( "$J" --no-setup-bend --wait 120 -- sleep 3 >/dev/null 2>&1; echo $? > "$T/w$i" ) & done
wait $(jobs -p | grep -v "^$mon$") 2>/dev/null; kill "$mon" 2>/dev/null; wait "$mon" 2>/dev/null
ok "$(cat "$T/w1" "$T/w2" "$T/w3" | tr '\n' ' ')" "0 0 0 " "three jobs on two slots all ran"
ok "$(sort -n "$T/peak" | tail -1)" 2 "at most two sandboxes at once"
ok "$(boxes)" 0 "all deleted"
grep -q "refused" "$BOAT_FAKE_DIR/calls"; ok $? 1 "no other subcommand used"
# ---- Boat's start windows (rolling), other clients, stale data, 429, unclear creates ----
F=$BOAT_FAKE_DIR; limits 100
# a fresh ledger per case, so our own start record is only that case's
fresh() { export BOAT_JOB_ROOT=$T/root$1; mkdir -p "$BOAT_JOB_ROOT"; echo "$P" > "$BOAT_JOB_ROOT/enabled"; : > "$F/starts"; }
fresh m
# minute window full (other clients' starts): refused at once with --wait 0, nothing created
echo "2 60 200" > "$F/startlimits"; now=$(date +%s); printf '%s\n' $((now-50)) $((now-50)) >> "$F/starts"
c0=$(newcalls); "$J" --no-setup-bend --wait 0 -- true >/dev/null 2>&1; ok $? 75 "minute full: refused"; ok "$(newcalls)" "$c0" "minute full: no create"
# ...and waits for it to roll over with --wait
out=$("$J" --no-setup-bend --wait 120 -- true 2>&1); ok $? 0 "minute full: waited then ran"
case $out in *"start limit per minute"*) ok 1 1 "minute wait reason" ;; *) ok 0 1 "minute wait reason" ;; esac
fresh h
# hour window full: refused with --wait 0; day window full: refused even with --wait
: > "$F/starts"; echo "12 3 200" > "$F/startlimits"; printf '%s\n' $((now-1000)) $((now-1000)) $((now-1000)) >> "$F/starts"
"$J" --no-setup-bend --wait 0 -- true >/dev/null 2>&1; ok $? 75 "hour full: refused"
: > "$F/starts"; echo "12 60 2" > "$F/startlimits"; printf '%s\n' $((now-40000)) $((now-40000)) >> "$F/starts"
c0=$(newcalls); "$J" --no-setup-bend --wait 300 -- true >/dev/null 2>&1; ok $? 75 "day full: refused without waiting"; ok "$(newcalls)" "$c0" "day full: no create"
# the race for the last start of the minute: exactly one creates
fresh r; echo "1 60 200" > "$F/startlimits"; c0=$(newcalls)
for i in 1 2; do ( "$J" --no-setup-bend --wait 0 -- sleep 1 >/dev/null 2>&1; echo $? > "$T/last$i" ) & done; wait
ok "$(sort "$T/last1" "$T/last2" | tr '\n' ' ')" "0 75 " "last start: one admitted"; ok $(( $(newcalls) - c0 )) 1 "last start: one create"
# stale limits (Boat still says 0 used) but our own record says the minute is full: refused
fresh s; echo "2 60 200" > "$F/startlimits"
"$J" --no-setup-bend -- true >/dev/null 2>&1; "$J" --no-setup-bend -- true >/dev/null 2>&1
echo "0 0 0" > "$F/stale"; c0=$(newcalls)
"$J" --no-setup-bend --wait 0 -- true >/dev/null 2>&1; ok $? 75 "stale limits: own record refuses"; ok "$(newcalls)" "$c0" "stale: no create"
rm -f "$F/stale"; : > "$F/starts"; echo "12 60 200" > "$F/startlimits"
# start limits missing: refused
sed 's/"starts":STARTS,//' "$F/limits.json" > "$F/l2" && mv "$F/l2" "$F/limits.json"; "$J" --no-setup-bend -- true >/dev/null 2>&1; ok $? 75 "start limits missing: refused"; limits 100
fresh q
# 429 twice, then created: backs off, one sandbox, three requests recorded
echo 2 > "$F/rate429"; echo 1 > "$F/retryafter"; c0=$(newcalls); b0=$(boxes)
out=$("$J" --no-setup-bend --wait 600 -- true 2>&1); rc=$?
ok $rc 0 "429: retried and ran"; ok $(( $(newcalls) - c0 )) 3 "429: three requests"; ok "$(boxes)" "$b0" "429: no sandbox left"
ok "$(grep -o 'retrying in [0-9]*s' <<<"$out" | tr '\n' ' ')" "retrying in 15s retrying in 30s " "429: backoff 15 s then 30 s"
ok "$(grep -c '"ev": "attempt"' "$BOAT_JOB_ROOT/ledger.jsonl")" 3 "429: every attempt recorded"
# 429 forever: gives up within --wait, no sandbox
echo 99 > "$F/rate429"; "$J" --no-setup-bend --wait 20 -- true >/dev/null 2>&1; ok $? 75 "429 forever: refused"; echo 0 > "$F/rate429"; ok "$(boxes)" 0 "429 forever: nothing made"
# an unclear create that did make a sandbox: adopted, used once, deleted, never a second create
echo made > "$F/unclear"; c0=$(newcalls)
"$J" --no-setup-bend -- true >/dev/null 2>&1; ok $? 0 "unclear create: adopted and ran"; ok $(( $(newcalls) - c0 )) 1 "unclear: one create"; ok "$(boxes)" 0 "unclear: deleted"
# an unclear create that made nothing: 76, not retried
echo none > "$F/unclear"; c0=$(newcalls)
"$J" --no-setup-bend -- true >/dev/null 2>&1; ok $? 76 "unclear, nothing made: 76"; ok $(( $(newcalls) - c0 )) 1 "unclear: not retried"
# an unclear create while another client made a sandbox of the same shape: neither adopted nor deleted
echo two > "$F/unclear"
"$J" --no-setup-bend -- true >/dev/null 2>&1; ok $? 76 "unclear with a look-alike: not adopted"
ok "$(boxes)" 2 "look-alike case: both left for a person"; rm -rf "$F/boxes"/*

st=$("$J" status --json)
ok "$(printf '%s' "$st" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["running"], d["orphans"], all(j["state"] in ("ended","swept","refused","ambiguous") for j in d["jobs"]), any(j.get("cost_cs",0)>0 and j.get("runtime_s",-1)>=0 and j.get("sandbox") for j in d["jobs"]))')" "0 0 True True" "status --json"

ok "$(python3 -c "import json; d=json.load(open('$BOAT_JOB_ROOT/status.json')); print(d['running'], 'month' in d, d['month']['cost_cs'] >= d['today']['cost_cs'] > 0)")" "0 True True" "status.json kept current"
ok "$(python3 -c "import json; d=json.load(open('$BOAT_JOB_ROOT/account.json')); print(d['active']['limit'], d['starts']['minute']['limit'], d['error'])")" "100 12 " "account.json from the last limits read"
echo "boat_job_test: $pass passed, $failn failed"
[ $failn = 0 ]
