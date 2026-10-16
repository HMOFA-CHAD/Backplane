#!/bin/sh
# Build tools/cef (backplane-cef) against a prebuilt CEF distribution.
#   scripts/build-cef.sh [OUT_DIR]     (default build/cef)
# The distribution is fetched once into $XDG_CACHE_HOME/backplane/cef/<ver>
# and checked against its published sha1. BACKPLANE_JOBS (2) caps ninja.
set -eu
CEF_VER='154.0.34+g14c5a08+chromium-154.0.8037.98'
CEF_SHA1=15c91ad767097217b2e82ba8b933fe30b134be69
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$ROOT/build/cef}
CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/backplane/cef
CEF_ROOT=$CACHE/${CEF_VER%%+*}
if [ ! -f "$CEF_ROOT/include/cef_version.h" ]; then
  NAME="cef_binary_${CEF_VER}_linux64_minimal.tar.bz2"
  mkdir -p "$CACHE/dl"
  curl -fsSL -o "$CACHE/dl/cef.tar.bz2" "https://cef-builds.spotifycdn.com/$(printf %s "$NAME" | sed 's/+/%2B/g')"
  echo "$CEF_SHA1  $CACHE/dl/cef.tar.bz2" | sha1sum -c -
  rm -rf "$CEF_ROOT.part" && mkdir -p "$CEF_ROOT.part"
  tar -xjf "$CACHE/dl/cef.tar.bz2" -C "$CEF_ROOT.part" --strip-components=1
  rm -f "$CACHE/dl/cef.tar.bz2"
  mv "$CEF_ROOT.part" "$CEF_ROOT"
fi
mkdir -p "$OUT"
cmake -S "$ROOT/tools/cef" -B "$OUT" -G Ninja -DCMAKE_BUILD_TYPE=Release -DPROJECT_ARCH=x86_64 \
  -DCEF_ROOT="$CEF_ROOT" -DCMAKE_CXX_COMPILER="${CXX:-clang++}" -DCMAKE_C_COMPILER="${CC:-clang}" >/dev/null
nice -n 19 ninja -C "$OUT" -j "${BACKPLANE_JOBS:-2}" backplane-cef
# the distribution ships libcef.so with debug info (1.4 GB); stripped ~0.25 GB
strip --strip-unneeded "$OUT/Release/libcef.so"
echo "$OUT/Release/backplane-cef"

