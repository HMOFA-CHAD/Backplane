#!/bin/sh
# Compile one C unit of scripts/build-app.sh to its object, or take the
# object of an earlier build of the very same text:
#
#   scripts/cc-unit.sh build/cc/backplane/u3.c
#
# The key is a hash of the unit's text, the compiler's identity and the
# flags (BP_CC_ID, BP_CFLAGS, set by build-app.sh), so a hit is exactly what
# the compile would write. BP_OBJ_CACHE is the folder ("" = no cache). A unit
# that includes the baked Google client (bp_google.h beside it) never enters
# the cache: its object holds a credential.
set -eu
c=$1
o=${c%.c}.o
dir=${BP_OBJ_CACHE:-}
key=""
if [ -n "$dir" ] && ! { [ -f "$(dirname "$c")/bp_google.h" ] && grep -q 'bp_google\.h' "$c"; }; then
  if command -v sha256sum >/dev/null 2>&1; then sum="sha256sum"; else sum="shasum -a 256"; fi
  key=$({ printf '%s\n%s\n' "${BP_CC_ID:-}" "${BP_CFLAGS:-}"; cat "$c"; } | $sum | cut -c1-40)
  if [ -f "$dir/$key.o" ]; then
    cp "$dir/$key.o" "$o" && touch "$dir/$key.o" && { echo "hit  $c" >&2; exit 0; }
  fi
fi
# shellcheck disable=SC2086
"$CC" -std=c11 $BP_CFLAGS -w -c "$c" -o "$o" || { echo "cc failed: $c" >&2; exit 255; }
if [ -n "$key" ]; then
  mkdir -p "$dir"
  cp "$o" "$dir/$key.o.$$" && mv "$dir/$key.o.$$" "$dir/$key.o"
fi
echo "cc   $c" >&2
