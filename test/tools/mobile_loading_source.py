#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,subprocess,os,sys,time,resource,re
fixture=Path('test/fixtures/mobile_loading_source_inputs.json');expected=sys.argv[1]
h=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert h(fixture)==expected
inputs=json.loads(fixture.read_text());out=Path('build/mobile-loading/semantic-source-v1');out.mkdir(parents=True,exist_ok=True)
resource.setrlimit(resource.RLIMIT_STACK,(1073741824,1073741824));env=dict(os.environ,BUN_JSC_maxPerThreadStackUsage='536870912',BEND_NO_TELEMETRY='1')
r={'status':'RUNNING_SOURCE_ONLY','inputs_sha256':expected,'phases':[],'scope':'Shared presentation, cursor/credit/bodycache laws, current phone send guard and web renderer semantic source tests/types only. No whole repository PROOF yet, native/service/mobile build, sockets, device/UI/render timing or speed gain acceptance.'}
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
 run('six-universal-laws',['bend','test/mobile_loading_proof.bend'],120)
 for label,path in [('startup-guards','test/mobile_loading_test.bend'),('retained-session-regressions','test/ios_session_test.bend'),('normal-web-renderer','test/web_presentation_test.bend')]:
  count=Path(path).read_text().count('C.Check.str(');run(label,['bend',path],180,count)
 run('recent-transport',['bun','test/tools/ios_recent_test.ts'],60)
 for name,path in [('mobile-entry','src/mobile/app.bend'),('server-entry','src/server/main.bend')]:
  run(name,['bash','-c','source scripts/bendok.sh; bend_check "$1"','entry',path],240)
 verify();r.update(status='PASS_FOCUSED_SOURCE_ONLY',new_universal_laws=6,end=time.time())
except BaseException as e:r.update(status='FAIL_SOURCE_ONLY',error=repr(e),end=time.time());save();raise
save();print(json.dumps(r,indent=2))
