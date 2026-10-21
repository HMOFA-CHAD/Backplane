#!/usr/bin/env python3
"""Affected cold-identity source gate only; no service/runtime build."""
from pathlib import Path
import hashlib,json,os,re,resource,subprocess,sys,time,tempfile,shutil
root=Path.cwd();fixture=Path('test/fixtures/desktop-identity-inputs.json');expected=sys.argv[1]
h=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert h(fixture)==expected
f=json.loads(fixture.read_text());out=Path('build/desktop-identity/source');out.mkdir(parents=True,exist_ok=True)
env=dict(os.environ,BEND_NO_TELEMETRY='1',BUN_JSC_maxPerThreadStackUsage='536870912');resource.setrlimit(resource.RLIMIT_STACK,(1073741824,1073741824))
report={'status':'RUNNING_SOURCE_ONLY','tree':sys.argv[2],'fixture_sha256':expected,'source_key':f['source_key'],'phases':[],'scope':'Canonical cold connection identity source/affected regression and whole repository PROOF only. No service build, socket/server, Electron, agent/provider/live/runtime acceptance.'}
def verify():
 assert h(fixture)==expected
 for n,v in f['portable_source'].items():assert h(n)==v,n
 assert f['source_key']==hashlib.sha256(json.dumps(f['portable_source'],sort_keys=True,separators=(',',':')).encode()).hexdigest()
def save(): (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
def run(name,cmd,limit,count=None,foreign=False,cwd=None,red=False):
 x={'name':name,'status':'RUNNING','start':time.time()};report['phases'].append(x);save();p=out/(name+'.log')
 try:
  with p.open('wb') as log:r=subprocess.run(cmd,env=env,cwd=cwd,stdout=log,stderr=subprocess.STDOUT,timeout=limit)
  text=p.read_text(errors='replace');x.update(exit=r.returncode,log_sha256=h(p),ok_count=sum(s.startswith('ok ') for s in text.splitlines()))
  if red:assert r.returncode!=0 and 'FAIL actual connection hello uses live canonical identity' in text and 'Error:' not in text,'red must fail semantic identity assertion'
  elif foreign:
   v=subprocess.run(['bash','-c','source scripts/bendok.sh; bend_verdict "$1" "$2"','proof',str(r.returncode),text],env=env,capture_output=True,text=True);x['repository_verdict_exit']=v.returncode;assert v.returncode==0
  else:
   assert r.returncode==0
   assert not re.search(r'^(FAIL|Error:|SOME PROOFS FAIL)',text,re.M)
  if count is not None:assert x['ok_count']==count,(name,x['ok_count'],count)
  x['status']='PASS';print(name+' PASS',flush=True)
 except BaseException as e:
  x.update(status='FAIL',error=repr(e));print(p.read_text(errors='replace')[-7000:] if p.exists() else str(e),flush=True);raise
 finally:x['end']=time.time();save()
try:
 verify()
 run('server-entry',['bash','-c','source scripts/bendok.sh; bend_check src/server/main.bend'],240)
 # Run the same regression against the exact b145 broker, in a disposable copy.
 with tempfile.TemporaryDirectory(prefix='identity-red-') as directory:
  scratch=Path(directory);shutil.copytree(root/'src',scratch/'src');(scratch/'test').mkdir();shutil.copy2(root/'test/desktop_identity_regression.bend',scratch/'test/desktop_identity_regression.bend');shutil.copy2(root/'test/fixtures/desktop_broker_before_identity.txt',scratch/'src/server/desktop-broker.bend')
  run('baseline-semantic-red',['bend','test/desktop_identity_regression.bend'],100,cwd=scratch,red=True)
 run('identity-regression',['bend','test/desktop_identity_regression.bend'],100,count=1)
 run('identity',['bend','test/desktop_identity_test.bend'],180,count=24)
 run('broker-affected',['bend','test/desktop_broker_test.bend'],120,count=50)
 run('whole-proof',['bend','PROOF.bend'],900,foreign=True)
 verify();report.update(status='PASS_COLD_IDENTITY_SOURCE_ONLY',assertions=75,new_laws=2,retained_other_browser_assertions=350,end=time.time())
except BaseException as e:report.update(status='FAIL_SOURCE_ONLY',error=repr(e),end=time.time());save();raise
save();print(json.dumps(report,indent=2))
