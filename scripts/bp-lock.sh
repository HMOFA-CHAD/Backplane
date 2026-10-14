#!/bin/sh
# A lease-backed hub lock, or a POSIX flock when no hub answers initially.
set -eu
name=${1:-}
case "$name" in ''|*[!A-Za-z0-9_-]*) echo 'usage: bp-lock.sh NAME -- CMD ARGS...' >&2; exit 2 ;; esac
[ ${#name} -le 64 ] || exit 2
shift
[ "${1:-}" = -- ] || { echo 'expected -- before command' >&2; exit 2; }
shift
[ "$#" -gt 0 ] || exit 2
url=${BACKPLANE_LOCK_URL:-http://127.0.0.1:${BACKPLANE_PORT:-3787}}
case "$url" in http://127.0.0.1:*|http://localhost:*) ;; *) echo 'lock URL must use loopback HTTP' >&2; exit 2 ;; esac
host=$(hostname | tr -cd 'A-Za-z0-9_.-')
# Include a nonce: a reused PID must never inherit a killed helper's lease.
nonce=$(mktemp -d "${TMPDIR:-/tmp}/bp-lock-client.XXXXXX")
holder="pid:$$@$host:${nonce##*/}"
body="{\"name\":\"$name\",\"holder\":\"$holder\",\"note\":\"bp-lock.sh\",\"wait\":true}"
post() { curl -fsS --connect-timeout 2 --max-time 35 -H 'Content-Type: application/json' -d "$body" "$url/lock/$1"; }
held() { printf '%s' "$1" | tr -d ' \n\r\t' | grep -q '"held":true'; }
if ! answer=$(post acquire 2>/dev/null); then
  rm -d "$nonce"
  path="${BACKPLANE_LOCK_DIR:-/tmp}/bp-$name.lock"
  if command -v flock >/dev/null 2>&1; then exec flock "$path" "$@"; fi
  # macOS has flock(2), but usually no flock(1).
  exec perl -MFcntl=:flock -e 'my $path = shift; open(my $f, ">>", $path) or die "$path: $!"; flock($f, LOCK_EX) or die "flock: $!"; $^F = fileno($f); exec @ARGV or die "exec: $!"' "$path" "$@"
fi
case "$answer" in *'"error"'*) echo "$answer" >&2; rm -d "$nonce"; exit 1 ;; esac
owner_pid=$$
owner_stamp=$(ps -o lstart= -p "$owner_pid")
cmd_pid= renew_pid=
cleanup() {
  trap - 0 1 2 15
  [ -z "$renew_pid" ] || { kill "$renew_pid" 2>/dev/null || :; wait "$renew_pid" 2>/dev/null || :; }
  [ -z "$cmd_pid" ] || { kill "$cmd_pid" 2>/dev/null || :; wait "$cmd_pid" 2>/dev/null || :; }
  post cancel >/dev/null 2>&1 || :
  post release >/dev/null 2>&1 || :
  rm -d "$nonce"
}
trap cleanup 0
trap 'exit 129' 1
trap 'exit 130' 2
trap 'exit 143' 15
lost_note() { case $(printf '%s' "$1" | tr -d ' \n\r\t') in *'"requeued":true'*) echo 'bp-lock: the hub had lost this waiter; queued again' >&2 ;; esac; }
# The wait belongs to this helper, never to an agent's MCP call.
n=0 down=0
while ! held "$answer"; do
  sleep 1
  n=$((n + 1))
  if [ "$n" -ge 30 ]; then
    n=0
    # A hub that is restarting is not the end of the wait: status retries below.
    if r=$(post renew 2>/dev/null); then lost_note "$r"; fi
  fi
  if next=$(post status 2>/dev/null); then
    down=0
    answer=$next
    case "$answer" in *'"error"'*) echo "$answer" >&2; exit 1 ;; esac
    lost_note "$answer"
  else
    [ "$down" -gt 0 ] || down=$(date +%s)
    # Give a restarting hub two minutes before giving up.
    [ $(($(date +%s) - down)) -lt 120 ] || { echo 'hub disappeared while waiting' >&2; exit 1; }
  fi
done
"$@" &
cmd_pid=$!
(
  pause_pid=
  trap '[ -z "$pause_pid" ] || kill "$pause_pid" 2>/dev/null || :; exit 0' 1 2 15
  while :; do
    sleep 30 &
    pause_pid=$!
    wait "$pause_pid"
    pause_pid=
    kill -0 "$owner_pid" 2>/dev/null || exit 0
    [ "$(ps -o lstart= -p "$owner_pid" 2>/dev/null)" = "$owner_stamp" ] || exit 0
    if ! answer=$(post renew) || ! held "$answer"; then
      # Fail closed well before the 90-second lease can lapse.
      kill "$cmd_pid" 2>/dev/null || :
      exit 1
    fi
  done
) &
renew_pid=$!
rc=0
wait "$cmd_pid" || rc=$?
cmd_pid=
exit "$rc"
