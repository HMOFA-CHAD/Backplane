from pathlib import Path
import json,hashlib,subprocess,os,sys,time
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
f=Path('test/fixtures/thin_coherent_inputs.json');assert sha(f)==sys.argv[1]
inputs=json.loads(f.read_text())
def verify():
 for p,h in inputs.items():assert sha(p)==h,p
verify()
retained=json.loads(Path('test/fixtures/thin_emitted_retained.json').read_text())
qualified=json.loads(Path('test/fixtures/thin_coherent_bend_qualified.json').read_text())
for p,h in qualified['bend_effect_closure'].items():assert sha(p)==h,p
bundle='test/fixtures/thin_saved_bridge_315468.js';fixture='test/fixtures/thin_saved_wire_315468.json'
assert sha(bundle)==retained['bridge_sha256'] and sha(fixture)==retained['fixture_sha256']
out=Path('build/mobile-loading/thin-coherent-emitted-v2');out.mkdir(parents=True,exist_ok=True)
r={'status':'RUNNING','retained':retained,'scope':'Only unfinished actual emitted production bridge controls using exact saved bundle/actual Bend fixture; no emission/build/service/device/UI/runtime acceptance.','start':time.time()}
def save(): (out/'validation.json').write_text(json.dumps(r,indent=2)+'\n')
save()
try:
 log=out/'native-thin-production-wire.log'
 with log.open('wb') as output:c=subprocess.run(['bun','test/tools/native_thin_emitted_307265.mjs',bundle,fixture],stdout=output,stderr=subprocess.STDOUT,timeout=180,env=dict(os.environ))
 r.update(exit=c.returncode,log_sha256=sha(log));save()
 assert c.returncode==0,log.read_text()[-14000:]
 result=json.loads(log.read_text().strip().splitlines()[-1]);assert result['pass'] and result['checks']>0
 verify()
 for p,h in qualified['bend_effect_closure'].items():assert sha(p)==h,p
 assert sha(bundle)==retained['bridge_sha256']
 r.update(status='PASS_COHERENT_SOURCE_EMITTED_BRIDGE_PROOF',actual_production_checks=result['checks'],bridge_sha256=sha(bundle),bridge_bytes=Path(bundle).stat().st_size)
except BaseException as e:
 r.update(status='FAIL',error=repr(e));save();raise
r['end']=time.time();save();print(json.dumps(r,indent=2))
