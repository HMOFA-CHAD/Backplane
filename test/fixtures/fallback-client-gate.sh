#!/bin/sh
# Shared desktop web/phone clients and the isolated hub's wire codec.
set -eu
. scripts/bendok.sh
bend_check src/web/app.bend
bend_check src/mobile/app.bend
bend_check test/wire/wire.bend
bend test/fallback_test.bend
bend test/fallback_settings_test.bend
bend src/web/index.html -o build/fallback-web
python3 scripts/js-unmarshal.py ../core/client.Ui build/fallback-web/chunk-*.js
python3 scripts/js-native.py build/fallback-web/chunk-*.js
cp src/web/sw.js build/fallback-web/sw.js
bend test/wire/index.html -o build/fallback-wire
scripts/build-mobile.sh --js
