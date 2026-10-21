#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
SDK_DIR="$PWD/build/phone-cache/android-sdk"
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 /opt/android-sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root="$SDK_DIR" 'platforms;android-35' 'build-tools;34.0.0' > build/phone-cache/android-sdk.log 2>&1
