#!/usr/bin/env bash
set -euo pipefail
export BEND_NO_TELEMETRY=1
ulimit -s 1048576
export BUN_JSC_maxPerThreadStackUsage=536870912
out=build/mailroom-room-recipient-gate
mkdir -p "$out"
source scripts/bendok.sh
python3 - "$1" <<'PY'
from pathlib import Path
import hashlib,json,sys
paths=['src/core/client.bend','LAWS.bend','PROOF.bend','test/mailroom_room_recipient_test.bend','test/mailroom_room_recipient_proof.bend','test/fixtures/mailroom-room-client-entrypoints.patch','test/tools/mailroom_room_recipient_gate.sh']
pins={p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in paths};key=hashlib.sha256(json.dumps(pins,sort_keys=True,separators=(',',':')).encode()).hexdigest()
assert key==sys.argv[1],(key,sys.argv[1]);Path('build/mailroom-room-recipient-gate/inputs.json').write_text(json.dumps({'key':key,'paths':pins},indent=2)+'\n')
PY
for f in src/core/client.bend test/mailroom_room_recipient_proof.bend test/mailroom_room_recipient_test.bend; do
 bend_check "$f" > "$out/$(basename "$f").check" 2>&1 || { tail -65 "$out/$(basename "$f").check"; exit 1; }
 echo "$f narrow CHECK PASS"
done
rc=0
bend test/mailroom_room_recipient_proof.bend > "$out/new-laws.log" 2>&1 || rc=$?
bend_verdict "$rc" "$(cat "$out/new-laws.log")" || { tail -65 "$out/new-laws.log"; exit 1; }
echo 'Three new recipient boundary laws PASS; no full PROOF rerun'
cp src/core/client.bend "$out/patched-client.bend"
restore() { cp "$out/patched-client.bend" src/core/client.bend; }
trap restore EXIT
git apply --reverse test/fixtures/mailroom-room-client-entrypoints.patch
bend test/mailroom_room_recipient_test.bend > "$out/before.log" 2>&1 || { tail -65 "$out/before.log"; exit 1; }
grep -q '^FAIL uncached B has no A text before RPC' "$out/before.log"
grep -q '^FAIL read.put single canonical Room at end' "$out/before.log"
restore
trap - EXIT
echo 'Actual old open/read.put entrypoints reproduced stale cross-room presentation and missing Room choice'
bend test/mailroom_room_recipient_test.bend > "$out/recipient.log" 2>&1 || { tail -65 "$out/recipient.log"; exit 1; }
grep -q '^ok ' "$out/recipient.log"
if grep -Eq '^(FAIL|Error:)' "$out/recipient.log"; then grep -E '^(FAIL|Error:)' "$out/recipient.log"; exit 1; fi
python3 - <<'PY'
from pathlib import Path
import hashlib,json,datetime
p=Path('build/mailroom-room-recipient-gate');pins=json.loads((p/'inputs.json').read_text())
for f,h in pins['paths'].items():assert hashlib.sha256(Path(f).read_bytes()).hexdigest()==h,f
r={'status':'PASS','at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source_key':pins['key'],'client_sha256':pins['paths']['src/core/client.bend'],'new_laws':3,'assertions':sum(x.startswith('ok ') for x in (p/'recipient.log').read_text().splitlines()),'logs':{x.name:hashlib.sha256(x.read_bytes()).hexdigest() for x in p.glob('*.log')},'scope':'Changed client target/open-bind closure only: new laws, real read.put/mail-to/mail-send payload, cross-room failed/stale reply ordering/cache tests. No full PROOF rerun, web rolealert/emission, standalone service/native/Electron/live/install/provider qualification. Prior3000556laws/761/fullPROOF retained on prior exact source; final composed proof required once.'}
(p/'validation.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2))
PY
