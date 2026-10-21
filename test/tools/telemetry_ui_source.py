from pathlib import Path
import hashlib,json,subprocess,os,sys,resource,re
resource.setrlimit(resource.RLIMIT_STACK,(1073741824,1073741824));env=dict(os.environ,BUN_JSC_maxPerThreadStackUsage='536870912')
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
f=Path('test/fixtures/telemetry_ui_inputs.json');assert sha(f)==sys.argv[1];inputs=json.loads(f.read_text())
out=Path('build/mobile-loading/telemetry-ui-source');out.mkdir(parents=True,exist_ok=True)
r={'status':'RUNNING','scope':'Exact telemetry module source handoff plus new human UI admission/privacy commit helpers and current server entry only. Existing worker/ingestion and module checks retained, no rerun. No full proof, build, service, UI/runtime, configured-package or installation acceptance.','phases':[]}
def save(): (out/'validation.json').write_text(json.dumps(r,indent=2)+'\n')
def verify():
 for p,h in inputs.items():assert sha(p)==h,p
try:
 verify()
 for name,cmd,count in [('ui-hook-check',['bash','-c','source scripts/bendok.sh; bend_check src/server/telemetry-ui.bend'],None),('ui-hook-tests',['bend','test/telemetry_ui_test.bend'],33),('server-entry',['bash','-c','source scripts/bendok.sh; bend_check src/server/main.bend'],None)]:
  p=out/(name+'.log');q={'name':name,'status':'RUNNING'};r['phases'].append(q);save()
  with p.open('wb') as log:c=subprocess.run(cmd,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=300)
  text=p.read_text();q.update(exit=c.returncode,sha256=sha(p),checks=sum(x.startswith('ok ') for x in text.splitlines()))
  if c.returncode or re.search(r'^(FAIL|Error:|SOME PROOFS FAIL)',text,re.M):print(text[-15000:],flush=True);raise AssertionError((name,c.returncode))
  if count is not None:assert q['checks']==count,(name,q['checks'],count)
  q['status']='PASS';save();print(name+' PASS',flush=True)
 verify();r['status']='PASS_CHANGED_HOOK_SOURCE_ONLY'
except BaseException as e:r.update(status='FAIL',error=repr(e));save();raise
save();print(json.dumps(r,indent=2))
