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
# artifacts from push runs on this repository's main branch are taken.
# Even a same-repository PR can edit its workflow and upload arbitrary C
# under a main input key. Deploys and releases build main; PR, dispatch and
# other branch artifacts are not trusted. The size in KEY.ok must match too.
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
# The newest unexpired artifact from main, then verify its producer event
# before downloading any C. Missing metadata or an API failure fails closed.
producer=$(timeout 20 gh api "repos/$repo/actions/artifacts?name=emit-$key&per_page=20" \
  --jq "[.artifacts[] | select(.expired == false and .workflow_run.head_repository_id == $rid and .workflow_run.repository_id == $rid and .workflow_run.head_branch == \"main\")][0] | select(. != null) | \"\(.id) \(.workflow_run.id)\"" 2>/dev/null) || exit 1
IFS=' ' read -r aid run <<EOF
$producer
EOF
case $aid in ''|*[!0-9]*) exit 1 ;; esac
case $run in ''|*[!0-9]*) exit 1 ;; esac
event=$(timeout 20 gh api "repos/$repo/actions/runs/$run" --jq .event 2>/dev/null) || exit 1
[ "$event" = push ] || exit 1
tmp=$(mktemp -d "${out%/*}/.emit-fetch.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' 0 1 2 15
timeout 300 gh api "repos/$repo/actions/artifacts/$aid/zip" >"$tmp/a.zip" 2>/dev/null || exit 1
( cd "$tmp" && python3 -c 'import sys, zipfile; zipfile.ZipFile("a.zip").extractall(".")' ) || exit 1
[ -f "$tmp/$key.c" ] && [ -f "$tmp/$key.ok" ] || exit 1
[ "$(cat "$tmp/$key.ok")" = "$(wc -c <"$tmp/$key.c" | tr -d ' ')" ] || exit 1
mv "$tmp/$key.c" "$out" || exit 1
echo "emit-fetch: emit-$key from $repo (artifact $aid)" >&2
