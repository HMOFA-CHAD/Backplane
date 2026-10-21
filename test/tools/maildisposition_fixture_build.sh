#!/usr/bin/env bash
set -euo pipefail
export BEND_NO_TELEMETRY=1 BUN_JSC_maxPerThreadStackUsage=536870912
ulimit -s 1048576
source scripts/bendok.sh
out=build/mailrun-dispositions-fixture
mkdir -p "$out"
bend_check test/maildisposition_fixture/fixture.bend > "$out/check.log" 2>&1 || { tail -65 "$out/check.log"; exit 1; }
bend test/maildisposition_fixture/index.html -o "$out/bundle" > "$out/emit.log" 2>&1 || { tail -65 "$out/emit.log"; exit 1; }
sha256sum src/core/{mcp,maildisposition,hub,mailcontinuity,mailrun}.bend test/maildisposition_fixture/* "$out"/bundle/*.js > "$out/inputs-and-bundle.sha256"
bun test/tools/maildisposition_fixture_host.ts --self-test "$out/bundle" "$out/self-test"
echo 'PASS exact production MCP fixture emission + fsynced journal/replay self-test; no app or provider execution'
