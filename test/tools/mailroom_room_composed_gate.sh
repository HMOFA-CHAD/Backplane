#!/bin/bash
set -euo pipefail
export BEND_NO_TELEMETRY=1 BUN_JSC_maxPerThreadStackUsage=536870912
ulimit -s 1048576
out=build/mailroom-room-composition/source-final
mkdir -p "$out"
source scripts/bendok.sh
verify() {
python3 - "${1:?Expected fixture SHA256 required}" <<'PY'
from pathlib import Path
import hashlib,json,sys
p=Path('test/fixtures/mailroom-room-composed-inputs.json');assert hashlib.sha256(p.read_bytes()).hexdigest()==sys.argv[1], 'Frozen portable fixture changed'
f=json.loads(p.read_text())
assert f['status']=='FROZEN_PENDING_FINAL_GATE' and f['entry']=='src/server/main.bend'
for n,h in f['public_source_sha256'].items():assert hashlib.sha256(Path(n).read_bytes()).hexdigest()==h,n
assert not Path('src/server/desktop-broker.bend').exists(), 'Browser excluded from urgent room composition'
assert not Path('src/core/browserinput.bend').exists(), 'Screenshot input excluded'
PY
}
verify "$1"
for name in src/server/main.bend src/web/app.bend src/web/mailroom.bend; do
  bend_check "$name" > "$out/$(basename "$name").check" 2>&1 || { tail -55 "$out/$(basename "$name").check"; exit 1; }
  echo "$name composed entry PASS"
done
# The actual client file changed after the prior 761-check gate. Recheck only
# its existing presentation suites; retain the other programs and new focused
# 38 client cases by exact receipts, rather than repeating the whole batch.
for name in mailroom_client mailroom_parity; do
  rc=0
  bend "test/${name}_test.bend" > "$out/$name.log" 2>&1 || rc=$?
  test "$rc" = 0 && ! rg '^FAIL|SOME PROOFS FAIL|Error:' "$out/$name.log" || { tail -55 "$out/$name.log"; exit 1; }
  echo "$name changed client closure PASS"
done
rc=0
bend PROOF.bend > "$out/proof.log" 2>&1 || rc=$?
bend_verdict "$rc" "$(cat "$out/proof.log")" || { tail -55 "$out/proof.log"; exit 1; }
verify "$1"
python3 - <<'PY'
from pathlib import Path
import hashlib,json,time
p=Path('test/fixtures/mailroom-room-composed-inputs.json');f=json.loads(p.read_text());o=Path('build/mailroom-room-composition/source-final')
x={'status':'PASS_FINAL_ROOM_COMPOSITION_SOURCE_ONLY','at':time.time(),'entry':f['entry'],'inputs_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'source_key':f['source_key'],'logs':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(o.iterdir()) if p.is_file()},'assertions':{n:sum(l.startswith('ok ') for l in (o/(n+'.log')).read_text().splitlines()) for n in ['mailroom_client','mailroom_parity']},'scope':'Final composed server/web entry checks, existing client presentation suites on changed closure and whole PROOF. Retain actual backend761, focusedclient38+3laws and web25/status12/combined transition controls by exact receipts. No service build/runtime/UI/provider/install/live setting.'}
(o/'validation.json').write_text(json.dumps(x,indent=2)+'\n');print(json.dumps(x,indent=2))
PY
