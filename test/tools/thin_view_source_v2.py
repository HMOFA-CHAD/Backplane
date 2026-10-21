from pathlib import Path
import json,hashlib,subprocess,os,resource,re,sys
out=Path('build/mobile-loading/thin-view-source-v2');out.mkdir(parents=True,exist_ok=True)
resource.setrlimit(resource.RLIMIT_STACK,(1073741824,1073741824));env=dict(os.environ,BUN_JSC_maxPerThreadStackUsage='536870912')
fixture=Path('test/fixtures/thin_view_inputs_v2.json');sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert sha(fixture)==sys.argv[1];inputs=json.loads(fixture.read_text());r={'status':'RUNNING','phases':[],'scope':'New selected-window pure normal production projection, query payloads and initial actual viewRPC server entry only; message handler/invalidation/bridge unfinished. No full proof/build/socket/device/runtime/gain acceptance.'}
def save(): (out/'validation.json').write_text(json.dumps(r,indent=2)+'\n')
def verify():
 for p,h in inputs.items():assert sha(p)==h,p
try:
 verify()
 for name,cmd,count in [('view-check',['bash','-c','source scripts/bendok.sh; bend_check src/server/thin-view.bend'],None),('view-tests',['bend','test/thin_view_test.bend'],21),('server-entry',['bash','-c','source scripts/bendok.sh; bend_check src/server/main.bend'],None)]:
  p=out/(name+'.log');q={'name':name,'status':'RUNNING'};r['phases'].append(q);save()
  with p.open('wb') as f:c=subprocess.run(cmd,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=300)
  text=p.read_text();q.update(exit=c.returncode,sha256=sha(p),checks=sum(x.startswith('ok ') for x in text.splitlines()))
  if c.returncode or re.search(r'^(FAIL|Error:|SOME PROOFS FAIL)',text,re.M):print(text[-15000:],flush=True);raise AssertionError((name,c.returncode))
  if count is not None:assert q['checks']==count,(name,q['checks'],count)
  q['status']='PASS';print(name+' PASS',flush=True);save()
 verify();r['status']='PASS_SOURCE_ONLY'
except BaseException as e:r.update(status='FAIL',error=repr(e));save();raise
save();print(json.dumps(r,indent=2))
