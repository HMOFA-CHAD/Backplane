#!/usr/bin/env bash
set -euo pipefail
export BEND_NO_TELEMETRY=1
ulimit -s 1048576
export BUN_JSC_maxPerThreadStackUsage=536870912
out=build/mail-ui-quiet
mkdir -p "$out"
source scripts/bendok.sh
python3 - "$1" <<'PY'
import hashlib,json,sys
from pathlib import Path
paths=['src/core/hub.bend','LAWS.bend','PROOF.bend','test/mail_ui_quiet_proof.bend','test/mail_ui_quiet_test.bend','test/fixtures/mail-ui-quiet.patch','test/tools/mail_ui_quiet_gate.sh','docs/harness/mailroom-ui-contract.md']
pins={p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in paths}
key=hashlib.sha256(json.dumps(pins,sort_keys=True,separators=(',',':')).encode()).hexdigest()
assert key==sys.argv[1],(key,sys.argv[1])
Path('build/mail-ui-quiet/inputs.json').write_text(json.dumps({'key':key,'paths':pins},indent=2)+'\n')
PY
for f in src/core/hub.bend test/mail_ui_quiet_proof.bend test/mail_ui_quiet_test.bend; do
 bend_check "$f" > "$out/$(basename "$f").check" 2>&1 || { tail -55 "$out/$(basename "$f").check"; exit 1; }
 echo "$f narrow PASS"
done
rc=0
bend test/mail_ui_quiet_proof.bend > "$out/new-laws.log" 2>&1 || rc=$?
bend_verdict "$rc" "$(cat "$out/new-laws.log")" || { tail -55 "$out/new-laws.log"; exit 1; }
echo 'Four additive UI/automation boundary laws PASS'
cp src/core/hub.bend "$out/patched-hub.bend"
restore() { cp "$out/patched-hub.bend" src/core/hub.bend; }
trap restore EXIT
git apply --reverse test/fixtures/mail-ui-quiet.patch
bend test/mail_ui_quiet_test.bend > "$out/before.log" 2>&1 || { tail -55 "$out/before.log"; exit 1; }
grep -q '^FAIL mail.list OFF human reply ok' "$out/before.log"
grep -q '^FAIL OFF read uses existing bounded body effect' "$out/before.log"
grep -q '^FAIL OFF bot reply exactly one body append' "$out/before.log"
restore
trap - EXIT
echo 'Three exact shipped OFF-state blockers reproduced'
for name in mail_ui_quiet mailfile mailrun maildisposition_routing maildisposition mailcontinuity auth; do
 bend "test/${name}_test.bend" > "$out/$name.log" 2>&1 || { tail -55 "$out/$name.log"; exit 1; }
 grep -q '^ok ' "$out/$name.log"
 if grep -Eq '^(FAIL|Error:)' "$out/$name.log"; then grep -E '^(FAIL|Error:)' "$out/$name.log"; exit 1; fi
 echo "$name PASS ($(grep -c '^ok ' "$out/$name.log") assertions)"
done
rc=0
bend PROOF.bend > "$out/proof.log" 2>&1 || rc=$?
bend_verdict "$rc" "$(cat "$out/proof.log")" || { tail -55 "$out/proof.log"; exit 1; }
python3 - <<'PY'
from pathlib import Path
import hashlib,json,datetime
p=Path('build/mail-ui-quiet');pins=json.loads((p/'inputs.json').read_text())
for f,h in pins['paths'].items():assert hashlib.sha256(Path(f).read_bytes()).hexdigest()==h,f
names=['mail_ui_quiet','mailfile','mailrun','maildisposition_routing','maildisposition','mailcontinuity','auth']
r={'status':'PASS','at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'base_tree':'45328b78acdd38c1d787810f0ce1113bf43a8b18','source_key':pins['key'],'assertions':{n:sum(x.startswith('ok ') for x in (p/(n+'.log')).read_text().splitlines()) for n in names},'logs':{x.name:hashlib.sha256(x.read_bytes()).hexdigest() for x in p.glob('*.log')},'scope':'Source/import/new laws/red-green/full PROOF and affected pure production cases only. Header replay dedup is pure fold evidence; actual successor service IO/UI/install pending. No provider/input replay or live setting change.'}
(p/'validation.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2))
PY
