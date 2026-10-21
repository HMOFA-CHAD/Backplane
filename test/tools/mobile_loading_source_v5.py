#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,subprocess,os,sys,time,resource,re
fixture=Path('test/fixtures/mobile_loading_source_inputs_v5.json');expected=sys.argv[1]
h=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert h(fixture)==expected
inputs=json.loads(fixture.read_text());out=Path('build/mobile-loading/semantic-source-v5');out.mkdir(parents=True,exist_ok=True)
resource.setrlimit(resource.RLIMIT_STACK,(1073741824,1073741824));env=dict(os.environ,BUN_JSC_maxPerThreadStackUsage='536870912',BEND_NO_TELEMETRY='1')
r={'status':'RUNNING_SOURCE_ONLY','inputs_sha256':expected,'phases':[],'scope':'ONLY unfinished genuine server entry type check after client alias correction. Seven v4 focused phases retained by frozen receipt, not rerun. No whole PROOF, build/runtime/native/device or gain acceptance.'}
def save(): (out/'validation.json').write_text(json.dumps(r,indent=2)+'\n')
def verify():
 assert h(fixture)==expected
 for p,digest in inputs.items():assert h(p)==digest,p

def run(name,cmd,limit,count=None):
 x={'name':name,'start':time.time(),'status':'RUNNING'};r['phases'].append(x);save();p=out/(name+'.log')
 try:
  with p.open('wb') as f:c=subprocess.run(cmd,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=limit)
  text=p.read_text(errors='replace');x.update(exit=c.returncode,sha256=h(p),checks=sum(s.startswith('ok ') for s in text.splitlines()))
  assert c.returncode==0,(name,c.returncode)
  assert not re.search(r'^(Error:|FAIL|SOME PROOFS FAIL)',text,re.M),name
  if count is not None:assert x['checks']==count,(name,x['checks'],count)
  x['status']='PASS';print(name+' PASS',flush=True)
 except BaseException:
  x['status']='FAIL';print(p.read_text(errors='replace')[-9000:] if p.exists() else name,flush=True);raise
 finally:x['end']=time.time();save()
try:
 verify()
 run('server-entry',['bash','-c','source scripts/bendok.sh; bend_check "$1"','entry','src/server/main.bend'],240)
 r['retained']=json.loads(Path('test/fixtures/mobile_loading_v4_retained.json').read_text())
 verify();r.update(status='PASS_FOCUSED_SOURCE_ONLY',retained_other_phases=7,end=time.time())
except BaseException as e:r.update(status='FAIL_SOURCE_ONLY',error=repr(e),end=time.time());save();raise
save();print(json.dumps(r,indent=2))
