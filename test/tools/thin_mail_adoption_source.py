from pathlib import Path
import hashlib,json,subprocess,os,sys,resource,re,time
resource.setrlimit(resource.RLIMIT_STACK,(1073741824,1073741824))
env=dict(os.environ,BUN_JSC_maxPerThreadStackUsage='536870912')
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
f=Path('test/fixtures/thin_mail_adoption_inputs.json');assert sha(f)==sys.argv[1]
inputs=json.loads(f.read_text());out=Path('build/mobile-loading/mailroom-adoption-source-01');out.mkdir(parents=True,exist_ok=True)
r={'status':'RUNNING','scope':'Canonical mailbox shared index cold adoption/incremental commit refresh; production semantic red, changed focused and prior actor guards, server entry and repository whole PROOF only. No service build/socket/Electron/native phone/UI/send/live acceptance.','start':time.time(),'phases':[]}
def save():(out/'validation.json').write_text(json.dumps(r,indent=2)+'\n')
def verify():
 for p,h in inputs.items():assert sha(p)==h,p

def run(name,cmd,timeout=300,red=False,proof=False):
 p=out/(name+'.log');q={'name':name,'start':time.time()};r['phases'].append(q);save()
 with p.open('wb') as log:c=subprocess.run(cmd,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=timeout)
 text=p.read_text(errors='replace');q.update(exit=c.returncode,sha256=sha(p),checks=sum(x.startswith('ok ') for x in text.splitlines()))
 if red:
  assert 'FAIL old adopted aggregate retains real canonical RPC room rows: got  want act-c,room:ra,room:rb,' in text,(name,text[-9000:])
  assert not re.search(r'^(Error:|SOME PROOFS FAIL)',text,re.M),(name,'red must execute production semantics',text[-9000:])
 elif proof:
  v=subprocess.run(['bash','-c','source scripts/bendok.sh; bend_verdict "$1" "$(cat "$2")"','_',str(c.returncode),str(p)],env=env,capture_output=True);q['repository_verdict_exit']=v.returncode
  assert v.returncode==0,(name,text[-12000:])
 else:assert c.returncode==0 and not re.search(r'^(FAIL|Error:|SOME PROOFS FAIL)',text,re.M),(name,text[-12000:])
 q.update(status='PASS',end=time.time());save();print(name+' PASS',flush=True)
try:
 verify()
 run('projection-check',['bend','--check-only','src/server/thin-mail.bend'])
 run('adoption-semantic-red',['bend','test/thin_mail_adoption_red.bend'],red=True)
 run('adoption',['bend','test/thin_mail_adoption_test.bend'])
 run('actor-affected',['bend','test/thin_mail_actor_test.bend'])
 run('server-entry',['bash','-c','source scripts/bendok.sh; bend_check src/server/main.bend'],timeout=360)
 run('whole-proof',['bend','PROOF.bend'],timeout=1200,proof=True)
 verify();r.update(status='PASS_SOURCE_ONLY',end=time.time())
except BaseException as e:r.update(status='FAIL',error=repr(e));save();raise
save();print(json.dumps(r,indent=2))
