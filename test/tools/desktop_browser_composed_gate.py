#!/usr/bin/env python3
"""One frozen desktop Browser source composition gate. No app or runtime."""
from pathlib import Path
import hashlib,json,os,re,resource,subprocess,sys,time
fixture=Path('test/fixtures/desktop-browser-final-inputs.json')
expected=sys.argv[1]
assert hashlib.sha256(fixture.read_bytes()).hexdigest()==expected,'frozen fixture changed'
f=json.loads(fixture.read_text());assert f['status']=='FROZEN_PENDING_FINAL_GATE'
out=Path('build/desktop-browser-composition/source-final');out.mkdir(parents=True,exist_ok=True)
env=os.environ.copy();env.update(BEND_NO_TELEMETRY='1',BUN_JSC_maxPerThreadStackUsage='536870912')
resource.setrlimit(resource.RLIMIT_STACK,(1073741824,1073741824))
report={'status':'RUNNING_SOURCE_ONLY','fixture_sha256':expected,'source_key':f['source_key'],'candidate_tree':sys.argv[2],'phases':[],'scope':'Final composed server/web entry checks, affected current Browser closures, eight added laws and whole PROOF. No service/native/Electron/provider/live/runtime/build/install/FPS acceptance.'}
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def verify():
 assert digest(fixture)==expected,'fixture changed'
 for p,h in f['public_source_sha256'].items():assert digest(p)==h,p
 for p,h in f['preserved_room'].items():assert digest(p)==h,p
 assert f['source_key']==hashlib.sha256(json.dumps(f['public_source_sha256'],sort_keys=True,separators=(',',':')).encode()).hexdigest()
def save():
 (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
def run(name,cmd,seconds,count=None,proof=False,foreign=False):
 phase={'name':name,'start':time.time(),'status':'RUNNING','command':cmd};report['phases'].append(phase);save()
 path=out/(name+'.log')
 try:
  with path.open('wb') as log:r=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,env=env,timeout=seconds)
  text=path.read_text(errors='replace');phase.update(exit=r.returncode,log_sha256=digest(path),ok_count=sum(l.startswith('ok ') for l in text.splitlines()))
  if foreign:
   verdict=subprocess.run(['bash','-c','source scripts/bendok.sh; bend_verdict "$1" "$2"','proof-verdict',str(r.returncode),text],env=env,capture_output=True,text=True)
   phase['repository_verdict_exit']=verdict.returncode
   assert verdict.returncode==0,name+' rejected by repository proof verdict'
  else:
   assert r.returncode==0, name+' returned '+str(r.returncode)
   assert not re.search(r'^(FAIL|Error:|SOME PROOFS FAIL)',text,re.M),name+' checker/assertion failure'
  if count is not None:assert phase['ok_count']==count,(name,phase['ok_count'],count)
  if proof and not foreign:assert 'ALL PROOFS CHECK' in text or 'All terms check' in text,name+' missing proof verdict'
  phase['status']='PASS'
 except BaseException as error:
  phase.update(status='FAIL',error=repr(error));print(path.read_text(errors='replace')[-7000:] if path.exists() else repr(error));raise
 finally:
  phase['end']=time.time();save()
 print(name+' PASS',flush=True)
try:
 verify()
 # Source-check entries through the repository's strict foreign-effect-aware
 # entry checker; whole PROOF uses the same strict repository verdict.
 retained=f['retained_server_entry']
 assert retained['phase']['status']=='PASS' and retained['phase']['exit']==0
 for path,sha in retained['source_closure'].items():assert digest(path)==sha,'retained server closure '+path
 log=retained['log_text'];assert hashlib.sha256(log.encode()).hexdigest()==retained['phase']['log_sha256']
 (out/'server-entry-retained.log').write_text(log)
 report['retained_server_entry']={k:retained[k] for k in ['work','validation_sha256','phase']}
 save();print('server-entry exact import closure RETAINED303883',flush=True)
 for name,path in [('web-entry','src/web/app.bend'),('web-bots-entry','src/web/bots.bend')]:
  run(name,['bash','-c','source scripts/bendok.sh; bend_check "$1"','gate',path],240)
 for name,count in f['affected_tests'].items():run(name,['bend','test/'+name+'.bend'],100,count)
 run('focused-new-laws',['bend','test/desktop_browser_laws.bend'],100,proof=True)
 run('whole-proof',['bend','PROOF.bend'],900,proof=True,foreign=True)
 verify();report.update(status='PASS_FINAL_DESKTOP_BROWSER_SOURCE_ONLY',end=time.time(),affected_assertions=sum(f['affected_tests'].values()),added_laws=8)
except BaseException as error:
 report.update(status='FAIL_SOURCE_ONLY',error=repr(error),end=time.time());save();raise
save();print(json.dumps(report,indent=2))
