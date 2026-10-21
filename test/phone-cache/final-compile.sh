#!/bin/sh
set -u
cd "$(dirname "$0")/../.."
android_rc=0
(cd mobile/android && ANDROID_HOME="$PWD/../../build/phone-cache/android-sdk" JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 ./gradlew --offline --no-daemon --max-workers=2 '-Dorg.gradle.jvmargs=-Xmx1g -Dfile.encoding=UTF-8' :app:compileDebugKotlin) > build/phone-cache/android-compile-final.log 2>&1 || android_rc=$?
ios_rc=0
ssh -o BatchMode=yes hs-mac-mini 'cd /tmp/bp-phone-cache-build-307265 && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project Backplane.xcodeproj -scheme Backplane -configuration Debug -sdk iphonesimulator -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/bp-phone-cache-dd-307265 CODE_SIGNING_ALLOWED=NO build' > build/phone-cache/ios-compile-final.log 2>&1 || ios_rc=$?
printf '{"android_exit":%d,"ios_exit":%d}\n' "$android_rc" "$ios_rc" > build/phone-cache/compile-result.json
cat build/phone-cache/compile-result.json
[ "$android_rc" -eq 0 ] && [ "$ios_rc" -eq 0 ]
