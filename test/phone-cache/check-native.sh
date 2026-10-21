#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
mkdir -p build/phone-cache
ssh -o BatchMode=yes hs-mac-mini 'cd /tmp/bp-phone-cache-red && swiftc ScreenCache.swift Pairing.swift main.swift -o screen-cache-test && ./screen-cache-test' > build/phone-cache/green-ios.log 2>&1
cat build/phone-cache/green-ios.log
cd mobile/android
ANDROID_HOME="$PWD/../../build/phone-cache/android-sdk" JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 ./gradlew --offline --no-daemon --max-workers=2 '-Dorg.gradle.jvmargs=-Xmx1g -Dfile.encoding=UTF-8' :app:compileDebugKotlin > ../../build/phone-cache/android-compile.log 2>&1
