#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,subprocess,os,sys,time,resource,re
fixture=Path('test/fixtures/mobile_loading_proof_resume_inputs.json');expected=sys.argv[1]
h=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert h(fixture)==expected
inputs=json.loads(fixture.read_text());out=Path('build/mobile-loading/final-proof-resume');out.mkdir(parents=True,exist_ok=True)
resource.setrlimit(resource.RLIMIT_STACK,(1073741824,1073741824));env=dict(os.environ,BUN_JSC_maxPerThreadStackUsage='536870912',BEND_NO_TELEMETRY='1')
r={'status':'RUNNING','inputs_sha256':expected,'phases':[],'scope':'ONLY unfinished whole repository PROOF after moving two new imports into legal headers. Three307844PASS webentry/23web/serverentry retained by exact receipt and unchanged dependency closure. All old/new law statements and proof bodies unchanged. Native compile/delta independent; no build/runtime/device gain.'}
def save(): (out/'validation.json').write_text(json.dumps(r,indent=2)+'\n')
def verify():
 assert h(fixture)==expected
 for p,d in inputs.items():assert h(p)==d,p

def run(name,cmd,limit,count=None,proof=False):
 x={'name':name,'start':time.time(),'status':'RUNNING'};r['phases'].append(x);save();p=out/(name+'.log')
 try:
  with p.open('wb') as f:c=subprocess.run(cmd,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=limit)
  text=p.read_text(errors='replace');x.update(exit=c.returncode,sha256=h(p),checks=sum(s.startswith('ok ') for s in text.splitlines()))
  if proof:
   q=subprocess.run(['bash','-c','source scripts/bendok.sh; bend_verdict "$1" "$(cat "$2")"','proof',str(c.returncode),str(p)],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=30)
   (out/'whole-proof-verdict.log').write_bytes(q.stdout);x.update(repository_verdict_exit=q.returncode,verdict_sha256=h(out/'whole-proof-verdict.log'))
   assert q.returncode==0,(name,c.returncode,q.stdout.decode(errors='replace'))
  else:
   assert c.returncode==0,(name,c.returncode)
   assert not re.search(r'^(Error:|FAIL|SOME PROOFS FAIL)',text,re.M),name
  if count is not None:assert x['checks']==count,(name,x['checks'],count)
  x['status']='PASS';print(name+' PASS',flush=True)
 except BaseException:
  x['status']='FAIL';print(p.read_text(errors='replace')[-9000:] if p.exists() else name,flush=True);raise
 finally:x['end']=time.time();save()
try:
 verify()
 run('whole-proof',['bend','PROOF.bend'],1200,proof=True)
 r['retained_307844']=json.loads(Path('test/fixtures/mobile_loading_final_retained.json').read_text())
 verify();r.update(status='PASS_FINAL_COMPOSED_SOURCE_AND_PROOF_ONLY',end=time.time())
except BaseException as e:r.update(status='FAIL_COMPOSED_SOURCE_ONLY',error=repr(e),end=time.time());save();raise
save();print(json.dumps(r,indent=2))
