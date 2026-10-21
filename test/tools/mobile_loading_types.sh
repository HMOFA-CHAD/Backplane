#!/usr/bin/env bash
set -euo pipefail
ulimit -s 1048576
export BUN_JSC_maxPerThreadStackUsage=536870912
source scripts/bendok.sh
out=build/mobile-loading/source-types-v1
mkdir -p "$out"
python3 - "$1" <<'PY'
import hashlib,json,pathlib,sys
p=pathlib.Path('test/fixtures/mobile_loading_inputs.json')
assert hashlib.sha256(p.read_bytes()).hexdigest()==sys.argv[1]
for name,digest in json.loads(p.read_text()).items():
 assert hashlib.sha256(pathlib.Path(name).read_bytes()).hexdigest()==digest,name
print('Frozen current50f4 + selective mobile startup source pins exact')
PY
for entry in src/mobile/app.bend src/server/main.bend; do
 name=$(basename "$(dirname "$entry")")
 rc=0
 bend "$entry" --check-only >"$out/$name.log" 2>&1 || rc=$?
 if ! bend_verdict "$rc" "$(cat "$out/$name.log")"; then cat "$out/$name.log"; exit 1; fi
 echo "$entry source entry PASS"
done
python3 - "$out" <<'PY'
import pathlib,json,hashlib,sys
out=pathlib.Path(sys.argv[1]); r={'status':'PASS_TYPES_ONLY','scope':'Current mobile App and genuine server entry types only; no proof, native phone/service build, protocol/runtime/device or performance acceptance.','logs':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in out.glob('*.log')}}
(out/'result.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r))
PY
