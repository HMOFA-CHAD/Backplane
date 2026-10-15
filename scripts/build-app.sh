#!/bin/sh
# Build a Bend program to a native binary in parallel, gently.
#
#   scripts/build-app.sh src/app/main.bend build/backplane
#
# `bend X -o bin` compiles one ~30 MB C file on one core (minutes, ~20 GB).
# Here bend emits the C, scripts/cc-split.py deals it into units, and clang
# compiles them side by side at low priority, so the machine stays usable.
# Builds on this machine share one lock (/tmp/bp-wt-build.lock, as the
# agents' builds do), so only one runs at a time, and stay on 4 cores.
#   BACKPLANE_JOBS  parallel compiles (default 4; 1 with BACKPLANE_LOW_MEM=1)
#   BACKPLANE_LOW_MEM=1  for small machines: bend's heap told 6 GiB and one
#                     compile at a time (slower; see the emit note below)
#   BACKPLANE_CPUS  the cores builds may use (default 0-3; "" for any)
#   BACKPLANE_CFLAGS  (default: -O3, as bend -o)
#   BACKPLANE_UNITS   C units the segments are dealt into (default 16)
#   BACKPLANE_OBJ_CACHE  objects by hash of unit text + compiler + flags
#                     (default ~/.cache/backplane-bend/obj; 0 = none), so a
#                     rebuild compiles only the units an edit changed
# The Google OAuth client "Connect Google" signs in with is baked in from
# BACKPLANE_GOOGLE_CLIENT_ID and _SECRET: the environment's (CI secrets), else
# a git-ignored .env here or in the main checkout (src/server/effects/google.c).
# BACKPLANE_GOOGLE_BAKE=0 bakes none (test/tools/google_e2e.ts).
set -eu
# (a caller already inside `flock /tmp/bp-wt-build.lock ...` holds it)
held() {
  p=$$
  while [ -n "$p" ] && [ "$p" -gt 1 ]; do
    case $(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null) in
      *flock*bp-wt-build.lock*) return 0 ;;
    esac
    p=$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null)
  done
  return 1
}
if [ -z "${BP_BUILD_LOCKED:-}" ] && command -v flock >/dev/null 2>&1 && ! held; then
  BP_BUILD_LOCKED=1 exec flock /tmp/bp-wt-build.lock "$0" "$@"
fi
src=$1
out=$2
cd "$(dirname "$0")/.."
low=${BACKPLANE_LOW_MEM:-0}
[ "$low" = 1 ] && jobs=${BACKPLANE_JOBS:-1} || jobs=${BACKPLANE_JOBS:-4}
# bend is a Bun program: JavaScriptCore sizes its heap to the machine's RAM
# and let the app's emit grow past 28 GB (systemd-oomd then killed whole
# desktop sessions). BUN_JSC_forceRAMSize tells it a smaller machine; it is
# a sizing hint, not a cap. The app's emit, measured (2026-10-15, bend
# 2.0.36, the same C byte for byte at each hint; peak RSS, wall):
#   12 GiB: 12.1 GB, 196 s   8 GiB: 8.5 GB, 224 s   6 GiB: 7.3 GB, 347 s
# (bp-coord/build-memory). The emit and the compiles run one after the other.
[ "$low" = 1 ] && hint=6442450944 || hint=8589934592
export BUN_JSC_forceRAMSize=${BUN_JSC_forceRAMSize:-$hint}
cpus=${BACKPLANE_CPUS-0-3}
pin=""
if [ -n "$cpus" ] && command -v taskset >/dev/null 2>&1; then
  pin="taskset -c $cpus"
fi
cflags=${BACKPLANE_CFLAGS:--O3}
CC=${CC:-clang}
export CC
# The app's C is cut into 16 units whatever the jobs: clang needs about 2.5 GB
# for each (7 GB for each of 4 bigger ones), compile time is the same in
# total, and a unit whose text is unchanged is taken from the object cache.
units=${BACKPLANE_UNITS:-16}
BP_CC_ID=$("$CC" --version 2>&1 | head -n 2 | tr '\n' ' ')
BP_OBJ_CACHE=${BACKPLANE_OBJ_CACHE-${XDG_CACHE_HOME:-$HOME/.cache}/backplane-bend/obj}
[ "$BP_OBJ_CACHE" = 0 ] && BP_OBJ_CACHE=""
if [ -n "$BP_OBJ_CACHE" ] && [ -d "$BP_OBJ_CACHE" ]; then
  # objects not used for 30 days go
  find "$BP_OBJ_CACHE" -name '*.o' -mtime +30 -exec rm -f {} + 2>/dev/null || true
fi
work="build/cc/$(basename "$out")"
mkdir -p "$work"
# bend's own emit runs on every core; keep it polite too. Its C is the
# same on every platform (effects choose with #ifdef), so it may be made
# on another machine: BACKPLANE_EMIT_ONLY=1 stops after writing it, and
# BACKPLANE_PREBUILT=1 compiles the one already there
if [ "${BACKPLANE_PREBUILT:-}" = 1 ] && [ -f "$work/all.c" ]; then
  echo "prebuilt $work/all.c"
else
  nice -n 19 $pin bend "$src" -o "$work/all.c" >/dev/null
fi
[ "${BACKPLANE_EMIT_ONLY:-}" = 1 ] && { echo "$work/all.c"; exit 0; }
n=$(nice -n 19 python3 scripts/cc-split.py "$work/all.c" "$work" "$units")
rm -f "$work"/u*.o
# the baked Google client, read from .env without running it
envval() {
  for f in .env "$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/../.env"; do
    [ -f "$f" ] || continue
    v=$(sed -n "s/^[[:space:]]*\(export[[:space:]]\{1,\}\)\{0,1\}$1=//p" "$f" | tail -n1 | tr -d "\"'\r")
    [ -n "$v" ] && { printf %s "$v"; return; }
  done
}
gid=${BACKPLANE_GOOGLE_CLIENT_ID:-$(envval BACKPLANE_GOOGLE_CLIENT_ID)}
gsec=${BACKPLANE_GOOGLE_CLIENT_SECRET:-$(envval BACKPLANE_GOOGLE_CLIENT_SECRET)}
rm -f "$work/bp_google.h"
if [ "${BACKPLANE_GOOGLE_BAKE:-1}" != 0 ] && [ -n "$gid" ] && [ -n "$gsec" ]; then
  case "$gid$gsec" in
    *[!A-Za-z0-9._-]*) echo "BACKPLANE_GOOGLE_CLIENT_ID/_SECRET: unexpected characters" >&2; exit 1 ;;
  esac
  printf '#define BP_GOOGLE_CLIENT_ID "%s"\n#define BP_GOOGLE_CLIENT_SECRET "%s"\n' "$gid" "$gsec" > "$work/bp_google.h"
  echo "baked Google client ${gid%%-*}-..."
fi
# the biggest units first, so the last ones to start are the small ones
export BP_CFLAGS="$cflags" BP_CC_ID BP_OBJ_CACHE
ls -S "$work"/u*.c | nice -n 19 $pin xargs -P "$jobs" -I{} scripts/cc-unit.sh {}
# the libraries bend -o links: X11 and ALSA when an effect includes them
libs=""
grep -q '#include <X11/' "$work/all.c" && libs="$libs -lX11"
grep -q '#include <alsa/' "$work/all.c" && libs="$libs -lasound"
nice -n 19 $pin "$CC" $cflags "$work"/u*.o -o "$out" -lpthread -lm $libs
echo "$out ($n units, $jobs jobs)"
