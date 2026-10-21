from pathlib import Path
import json,hashlib,subprocess,os,resource,time,re,sys
out=Path('build/mobile-loading/thin-index-source');out.mkdir(parents=True,exist_ok=True)
resource.setrlimit(resource.RLIMIT_STACK,(1073741824,1073741824));env=dict(os.environ,BUN_JSC_maxPerThreadStackUsage='536870912')
fixture=Path('test/fixtures/thin_index_inputs.json');sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert sha(fixture)==sys.argv[1];inputs=json.loads(fixture.read_text())
r={'status':'RUNNING','phases':[],'scope':'New derived page/search index and shared thin transport/compact-session checks only; no server wiring/build/socket/native/UI or performance acceptance'}
def save(): (out/'validation.json').write_text(json.dumps(r,indent=2)+'\n')
def verify():
 for p,h in inputs.items():assert sha(p)==h,p
try:
 verify()
 for name,cmd,count in [('index-check',['bash','-c','source scripts/bendok.sh; bend_check src/core/thin.bend'],None),('index-tests',['bend','test/thin_index_test.bend'],24),('transport',['bun','test/tools/thin_transport_test.mjs'],29)]:
  p=out/(name+'.log');q={'name':name,'status':'RUNNING'};r['phases'].append(q);save()
  with p.open('wb') as f:c=subprocess.run(cmd,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=180)
  text=p.read_text();q.update(exit=c.returncode,sha256=sha(p),checks=sum(x.startswith('ok ') for x in text.splitlines()))
  if c.returncode or re.search(r'^(FAIL|Error:|SOME PROOFS FAIL)',text,re.M):print(text,flush=True);raise AssertionError((name,c.returncode))
  if count is not None:assert q['checks']==count,(name,q['checks'],count)
  q['status']='PASS';print(name+' PASS',flush=True);save()
 verify();r['status']='PASS_SOURCE_ONLY'
except BaseException as e:r.update(status='FAIL',error=repr(e));save();raise
save();print(json.dumps(r,indent=2))
