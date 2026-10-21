#!/usr/bin/env bash
set -euo pipefail
export BEND_NO_TELEMETRY=1
ulimit -s 1048576
export BUN_JSC_maxPerThreadStackUsage=536870912
out=build/mailrun-routing-v1
mkdir -p "$out"
source scripts/bendok.sh
python3 - "$1" <<'PY'
import hashlib,json,sys
from pathlib import Path
paths=['src/core/bothub.bend','LAWS.bend','PROOF.bend','test/maildisposition_routing_test.bend','test/fixtures/maildisposition-routing-before.patch','test/tools/maildisposition_routing_gate.sh']
pins={p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in paths}
key=hashlib.sha256(json.dumps(pins,sort_keys=True,separators=(',',':')).encode()).hexdigest()
assert key==sys.argv[1],(key,sys.argv[1])
Path('build/mailrun-routing-v1/inputs.json').write_text(json.dumps({'key':key,'paths':pins},indent=2)+'\n')
PY
for f in src/core/bothub.bend test/maildisposition_routing_test.bend; do
  bend_check "$f" > "$out/$(basename "$f").check" 2>&1 || { tail -55 "$out/$(basename "$f").check"; exit 1; }
  echo "$f narrow PASS"
done
python3 - <<'PY'
from pathlib import Path
law=Path('LAWS.bend').read_text().split('# Every production listing route retains the current thread\'s scoped tools.\n')[1]
proof=Path('PROOF.bend').read_text().split('def Laws.mail_disposition_bot_router_scoped_tools',1)[1]
imports='import Base\nimport ../../src/core/bothub.bend as BHS\nimport ../../src/core/model.bend as M\nimport ../../src/core/hub.bend as H\nimport ../../src/core/json.bend as J\nimport ../../src/core/mcp.bend as MC\nimport ../../src/core/order.bend as ORD\n'
Path('build/mailrun-routing-v1/new-laws.bend').write_text(imports+law+'\ndef mail_disposition_bot_router_scoped_tools'+proof.replace('def Laws.','def '))
PY
rc=0
bend "$out/new-laws.bend" > "$out/new-laws.log" 2>&1 || rc=$?
bend_verdict "$rc" "$(cat "$out/new-laws.log")" || { tail -55 "$out/new-laws.log"; exit 1; }
echo 'Two universal production router laws PASS'
cp src/core/bothub.bend "$out/patched-bothub.bend"
restore() { cp "$out/patched-bothub.bend" src/core/bothub.bend; }
trap restore EXIT
git apply --reverse test/fixtures/maildisposition-routing-before.patch
bend test/maildisposition_routing_test.bend > "$out/before.log" 2>&1 || { tail -55 "$out/before.log"; exit 1; }
test "$(grep -c '^FAIL ' "$out/before.log")" = 4 || { grep -E '^(FAIL|Error:)' "$out/before.log"; exit 1; }
restore
trap - EXIT
echo 'Four ff53 production Bots.mcp.o advertisement/payload regressions reproduced'
for name in maildisposition_routing maildisposition bots mailrun mailcontinuity; do
  bend "test/${name}_test.bend" > "$out/$name.log" 2>&1 || { tail -55 "$out/$name.log"; exit 1; }
  grep -q '^ok ' "$out/$name.log"
  if grep -Eq '^(FAIL|Error:)' "$out/$name.log"; then grep -E '^(FAIL|Error:)' "$out/$name.log"; exit 1; fi
  echo "$name PASS ($(grep -c '^ok ' "$out/$name.log") assertions)"
done
rc=0
bend PROOF.bend > "$out/proof.log" 2>&1 || rc=$?
bend_verdict "$rc" "$(cat "$out/proof.log")" || { tail -55 "$out/proof.log"; exit 1; }
python3 - <<'PY'
import hashlib,json,datetime
from pathlib import Path
out=Path('build/mailrun-routing-v1'); pins=json.loads((out/'inputs.json').read_text())
for p,h in pins['paths'].items():assert hashlib.sha256(Path(p).read_bytes()).hexdigest()==h,p
names=['maildisposition_routing','maildisposition','bots','mailrun','mailcontinuity']
result={'status':'PASS','at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'base_tree':'ff53d83594a231e85bfa78488d7b4722a9627fec','source_key':pins['key'],'assertions':{n:sum(s.startswith('ok ') for s in (out/(n+'.log')).read_text().splitlines()) for n in names},'logs':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in out.glob('*.log')},'scope':'Narrow production source/import checks, two new router laws, four red regressions, affected pure cases and whole PROOF only; no app/provider/native/retry/rollout acceptance'}
(out/'validation.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
PY
