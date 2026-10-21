#!/bin/sh
# Fetch an emitted C file that CI already made from exactly these inputs, so
# a build here (deploy_main, a release, another CI job) skips the emit:
#
#   scripts/emit-fetch.sh KEY OUT.c     exit 0 with OUT.c written, else 1
#
# KEY is build-app.sh's emit key (scripts/inputs-key.sh over everything bend
# reads, the same on every machine for the same sources and bend release).
# CI's Build job uploads its emit as the artifact "emit-KEY": KEY.c and
# KEY.ok (the C's size), as build-app.sh keeps them in its emit cache. Only
# artifacts of runs on this repository's own branches are taken (a fork's
# pull request runs its own workflow and could name any artifact), and only
# whole: the size in KEY.ok must match.
# Needs gh (signed in, or GH_TOKEN/GITHUB_TOKEN with actions:read).
# BACKPLANE_EMIT_REMOTE=0 turns it off.
set -u
key=${1:?emit-fetch.sh: a key}
out=${2:?emit-fetch.sh: an output file}
[ "${BACKPLANE_EMIT_REMOTE:-1}" = 0 ] && exit 1
command -v gh >/dev/null 2>&1 || exit 1
cd "$(dirname "$0")/.." || exit 1
repo=${BACKPLANE_EMIT_REPO:-}
if [ -z "$repo" ]; then
  url=$(git remote get-url origin 2>/dev/null) || exit 1
  repo=$(printf '%s\n' "$url" | sed -n 's#.*github\.com[:/]\([^/]*/[^/.]*\)\(\.git\)\{0,1\}$#\1#p')
  [ -n "$repo" ] || exit 1
fi
rid=$(timeout 20 gh api "repos/$repo" --jq .id 2>/dev/null) || exit 1
# the newest unexpired artifact of that name made in this repository
aid=$(timeout 20 gh api "repos/$repo/actions/artifacts?name=emit-$key&per_page=20" \
  --jq "[.artifacts[] | select(.expired == false and .workflow_run.head_repository_id == $rid and .workflow_run.repository_id == $rid)][0].id // empty" 2>/dev/null) || exit 1
[ -n "$aid" ] || exit 1
tmp=$(mktemp -d "${out%/*}/.emit-fetch.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' 0 1 2 15
timeout 300 gh api "repos/$repo/actions/artifacts/$aid/zip" >"$tmp/a.zip" 2>/dev/null || exit 1
( cd "$tmp" && python3 -c 'import sys, zipfile; zipfile.ZipFile("a.zip").extractall(".")' ) || exit 1
[ -f "$tmp/$key.c" ] && [ -f "$tmp/$key.ok" ] || exit 1
[ "$(cat "$tmp/$key.ok")" = "$(wc -c <"$tmp/$key.c" | tr -d ' ')" ] || exit 1
mv "$tmp/$key.c" "$out" || exit 1
echo "emit-fetch: emit-$key from $repo (artifact $aid)" >&2
