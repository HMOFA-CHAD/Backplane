from pathlib import Path
import hashlib,json,subprocess,os,sys,resource,re,time
resource.setrlimit(resource.RLIMIT_STACK,(1073741824,1073741824))
env=dict(os.environ,BUN_JSC_maxPerThreadStackUsage='536870912')
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
f=Path('test/fixtures/thin_coherent_inputs.json');assert sha(f)==sys.argv[1]
inputs=json.loads(f.read_text());out=Path('build/mobile-loading/thin-coherent-source-v4');out.mkdir(parents=True,exist_ok=True)
r={'status':'RUNNING','scope':'Coherent actor/live/projection, coalesced navigation/Usage/status UI, native Bend adapters/bridge, normal Mailroom and whole PROOF. Product native compilation and actual service/UI/device acceptance remain separate.','phases':[],'start':time.time()}
def save(): (out/'validation.json').write_text(json.dumps(r,indent=2)+'\n')
def verify():
 for p,h in inputs.items():assert sha(p)==h,p

def run(name,cmd,timeout=300,proof=False,checks=False):
 p=out/(name+'.log');q={'name':name,'status':'RUNNING','start':time.time()};r['phases'].append(q);save()
 with p.open('wb') as log:c=subprocess.run(cmd,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=timeout)
 text=p.read_text(errors='replace');q.update(exit=c.returncode,sha256=sha(p),end=time.time(),checks=sum(x.startswith('ok ') for x in text.splitlines()))
 if proof:
  verdict=subprocess.run(['bash','-c','source scripts/bendok.sh; bend_verdict "$1" "$(cat "$2")"','_',str(c.returncode),str(p)],env=env,capture_output=True);q['repository_verdict_exit']=verdict.returncode
  assert verdict.returncode==0,(name,c.returncode,text[-14000:])
 else:
  assert c.returncode==0 and not re.search(r'^(FAIL|Error:|SOME PROOFS FAIL)',text,re.M),(name,c.returncode,text[-14000:])
  if checks:assert q['checks']>0,(name,'no executed assertions')
 q['status']='PASS';save();print(name+' PASS',flush=True)
try:
 verify()
 retained=json.loads(Path('test/fixtures/thin_coherent_retained.json').read_text())
 for name,receipt in retained['retained'].items():
  for path,h in receipt['closure'].items():assert sha(path)==h,(name,path)
  r.setdefault('retained_phases',{})[name]=receipt['phase']
 save()
 for name,path in [('mail-actor','test/thin_mail_actor_test.bend'),('live-dispatch','test/thin_live_test.bend'),('native-bend-adapters','test/thin_mobile_adapter_test.bend'),('route','test/thin_route_test.bend'),('index','test/thin_index_test.bend'),('message','test/thin_message_test.bend'),('view','test/thin_view_test.bend'),('wire','test/thin_wire_test.bend'),('navigation-composed','test/uber_navigation_test.bend'),('usage-ui-composed','test/usage_page_ui_test.bend'),('signal-ui-composed','test/signal_ui_test.bend')]:
  if name not in retained['retained']:run(name,['bend',path],checks=True)
 if 'timeline-layout' not in retained['retained']:run('timeline-layout',['bend','test/thin_timeline_test.bend'],checks=True)
 for name,path in [('server-entry','src/server/main.bend'),('web-entry','src/web/app.bend'),('mobile-entry','src/mobile/app.bend')]:
  if name not in retained['retained']:run(name,['bash','-c','source scripts/bendok.sh; bend_check "$1"','_',path],timeout=360)
 run('whole-proof',['bend','PROOF.bend'],timeout=1200,proof=True)
 if os.environ.get('BP_COHERENT_PHASE')=='bend':
  verify();r.update(status='PASS_COHERENT_BEND_PHASE_EMISSION_PENDING',end=time.time())
  save();print(json.dumps(r,indent=2));sys.exit(0)

 run('host-wire-emission',['bend','test/thin_host_wire.html','-o',str(out/'host-wire')],timeout=300)
 chunks=list((out/'host-wire').glob('chunk-*.js'));assert len(chunks)==1,('host-wire chunk count',len(chunks))
 run('host-wire-production',['bun',str(chunks[0])],timeout=120)

 # Actual bridge is emitted once. The later genuine service build reuses this
 # pinned bundle, rather than producing a second unreviewed phone resource.
 run('emitted-native-fixture',['bend','test/thin_emitted_fixture.bend'],timeout=180)
 run('mobile-bridge-emission',['bash','scripts/build-mobile.sh','--js'],timeout=420)
 run('legacy-mailroom-bridge',['bun','test/tools/ios_mailroom_bridge_test.ts','mobile/build/assets/bridge.js',str(out/'legacy-mailroom.json')],timeout=180)
 # The native owner supplies source-specific integrated controls; paths are
 # bound in the immutable input manifest before this runner is admitted.
 config=json.loads(Path('test/fixtures/thin_coherent_commands.json').read_text())
 for spec in config:
  run(spec['name'],spec['command'],timeout=spec.get('timeout',180))
 verify();r.update(status='PASS_COHERENT_SOURCE_EMITTED_BRIDGE_PROOF',bridge_sha256=sha('mobile/build/assets/bridge.js'),bridge_bytes=Path('mobile/build/assets/bridge.js').stat().st_size)
except SystemExit:
 raise
except BaseException as e:
 r.update(status='FAIL',error=repr(e));save();raise
r['end']=time.time();save();print(json.dumps(r,indent=2))
