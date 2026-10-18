#!/bin/sh
set -eu
# Full integration gate after rebase and native-layout/server factoring.
export BUN_JSC_forceRAMSize=4294967296 CHECK_JOBS=1 TEST_JOBS=2
scripts/check.sh all
scripts/test.sh
