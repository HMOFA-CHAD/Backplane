#!/usr/bin/env bash
set -euo pipefail
export BEND_NO_TELEMETRY=1
ulimit -s 1048576
export BUN_JSC_maxPerThreadStackUsage=536870912
out=build/mailroom-room-gate
mkdir -p "$out"
source scripts/bendok.sh
python3 - "$1" <<'PY'
import hashlib,json,sys
from pathlib import Path
paths=['src/core/mailroom_history.bend','src/core/hub.bend','src/core/bothub.bend','src/core/client.bend','src/server/mailstore.bend','src/server/server.bend','LAWS.bend','PROOF.bend','test/mailroom_room_test.bend','test/mailroom_room_proof.bend','test/fixtures/mailroom-room-before.patch','test/tools/mailroom_room_gate.sh']
pins={p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in paths}
key=hashlib.sha256(json.dumps(pins,sort_keys=True,separators=(',',':')).encode()).hexdigest()
assert key==sys.argv[1],(key,sys.argv[1])
prior=Path('build/mailroom-room-gate/inputs.json')
checked=['src/core/mailroom_history.bend','src/core/hub.bend','src/core/bothub.bend','src/core/client.bend','src/server/mailstore.bend','src/server/server.bend','test/mailroom_room_proof.bend']
keep=prior.exists() and all(json.loads(prior.read_text())['paths'].get(p)==pins[p] and Path('build/mailroom-room-gate/'+Path(p).name+'.check').exists() for p in checked)
Path('build/mailroom-room-gate/retain-preflight').write_text('yes' if keep else 'no')
Path('build/mailroom-room-gate/inputs.json').write_text(json.dumps({'key':key,'paths':pins},indent=2)+'\n')
PY
for f in src/core/mailroom_history.bend src/core/hub.bend src/core/bothub.bend src/core/client.bend src/server/mailstore.bend src/server/server.bend test/mailroom_room_proof.bend test/mailroom_room_test.bend; do
 if [ "$f" != test/mailroom_room_test.bend ] && [ "$(cat "$out/retain-preflight")" = yes ]; then echo "$f retained exact-source CHECK PASS"; continue; fi
 bend_check "$f" > "$out/$(basename "$f").check" 2>&1 || { tail -55 "$out/$(basename "$f").check"; exit 1; }
 echo "$f narrow CHECK PASS"
done
rc=0
bend test/mailroom_room_proof.bend > "$out/new-laws.log" 2>&1 || rc=$?
bend_verdict "$rc" "$(cat "$out/new-laws.log")" || { tail -65 "$out/new-laws.log"; exit 1; }
echo 'Six additive room-policy production laws PASS'
# The shipped entrypoints remain callable in the regression program. New
# pure helpers and exact lookup are not removed from this red fixture.
for f in src/core/hub.bend src/core/bothub.bend src/core/client.bend src/server/server.bend; do
 mkdir -p "$out/patched/$(dirname "$f")"
 cp "$f" "$out/patched/$f"
done
restore() {
 for f in src/core/hub.bend src/core/bothub.bend src/core/client.bend src/server/server.bend; do cp "$out/patched/$f" "$f"; done
}
trap restore EXIT
git apply --reverse test/fixtures/mailroom-room-before.patch
bend test/mailroom_room_test.bend > "$out/before.log" 2>&1 || { tail -65 "$out/before.log"; exit 1; }
grep -q '^FAIL OFF exactly one append' "$out/before.log"
grep -q '^FAIL canonical OFF aggregate index sees room' "$out/before.log"
grep -q '^FAIL actual room page /3' "$out/before.log"
restore
trap - EXIT
echo 'Three shipped human room send/index/body failures reproduced'
for name in mailroom_room mail_ui_quiet mailstore mailfile mailroom_client mailroom_parity bots mailrun maildisposition_routing mailcontinuity auth; do
 bend "test/${name}_test.bend" > "$out/$name.log" 2>&1 || { tail -65 "$out/$name.log"; exit 1; }
 grep -q '^ok ' "$out/$name.log"
 if grep -Eq '^(FAIL|Error:)' "$out/$name.log"; then grep -E '^(FAIL|Error:)' "$out/$name.log"; exit 1; fi
 echo "$name PASS ($(grep -c '^ok ' "$out/$name.log") assertions)"
done
rc=0
bend PROOF.bend > "$out/proof.log" 2>&1 || rc=$?
bend_verdict "$rc" "$(cat "$out/proof.log")" || { tail -65 "$out/proof.log"; exit 1; }
python3 - <<'PY'
from pathlib import Path
import hashlib,json,datetime
p=Path('build/mailroom-room-gate');pins=json.loads((p/'inputs.json').read_text())
for f,h in pins['paths'].items():assert hashlib.sha256(Path(f).read_bytes()).hexdigest()==h,f
names=['mailroom_room','mail_ui_quiet','mailstore','mailfile','mailroom_client','mailroom_parity','bots','mailrun','maildisposition_routing','mailcontinuity','auth']
r={'status':'PASS','at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'base_tree':'47f5910eb45b9182278ca2271d8c3d92d43a6a80','source_key':pins['key'],'assertions':{n:sum(x.startswith('ok ') for x in (p/(n+'.log')).read_text().splitlines()) for n in names},'logs':{x.name:hashlib.sha256(x.read_bytes()).hexdigest() for x in p.glob('*.log')},'scope':'Isolated source/import/new laws/red-green, actual JS-target MailJob/MailStore public fixture IO, pure client/router controls and whole PROOF. No successor native service/Electron/live/install/provider acceptance.'}
(p/'validation.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2))
PY
