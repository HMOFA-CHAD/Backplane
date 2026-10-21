#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
ssh -o BatchMode=yes hs-mac-mini 'cd /tmp/bp-phone-cache-red && swiftc ScreenCache.swift Pairing.swift main.swift -o screen-cache-test && ./screen-cache-test && swiftc PresentationReadiness.swift readiness.swift -o readiness-test && ./readiness-test' > build/phone-cache/ios-helper-runtime.log 2>&1
cat build/phone-cache/ios-helper-runtime.log
