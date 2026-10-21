from pathlib import Path
import hashlib,json,subprocess,os,sys,resource,re,time
resource.setrlimit(resource.RLIMIT_STACK,(1073741824,1073741824))
env=dict(os.environ,BUN_JSC_maxPerThreadStackUsage='536870912',BP_NATIVE_THIN_SOURCE_ROOT=os.getcwd(),BP_PAGING_SOURCE_ROOT=os.getcwd())
h=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
f=Path('test/fixtures/native06_emit_inputs.json');assert h(f)==sys.argv[1];inputs=json.loads(f.read_text())
out=Path('build/mobile-loading/native06-emitted-01');out.mkdir(parents=True,exist_ok=True)
r={'status':'RUNNING','start':time.time(),'phases':[],'scope':'Necessary actual JS bridge emission and affected native source/legacy/production wire/actual07 replay only; retained317878 Bend/server proof and318338 service/web unchanged. No C/service/native platform build, socket/device/UI/runtime/install or stable release acceptance.'}
def save():(out/'validation.json').write_text(json.dumps(r,indent=2)+'\n')
def verify():
 for p,x in inputs.items():assert h(p)==x,p
 consumed=json.loads(Path('test/fixtures/native06_consumed.json').read_text())
 assert consumed['js06_receipt_sha256']=='13e01b0ca8fb6c734808d6c3705eb1cee5ae1580b9951ccdabfc7e0775539b7e'
 assert consumed['native04_receipt_sha256']=='46d8a64189c1bc84f6cb13c0b8e57a277e6f568d1abb63679390814c5e61cf2c'
 for p,x in consumed['consumer_pins'].items():assert h(p)==x,p
 for p,x in json.loads(Path('test/fixtures/native06_retained_bend.json').read_text()).items():assert h(p)==x,p
 return consumed

def run(name,cmd,timeout=180):
 log=out/(name+'.log');q={'name':name,'start':time.time()};r['phases'].append(q);save()
 with log.open('wb') as stream:c=subprocess.run(cmd,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=timeout)
 text=log.read_text(errors='replace');q.update(exit=c.returncode,sha256=h(log),end=time.time())
 assert c.returncode==0 and not re.search(r'^(FAIL|Error:|SOME PROOFS FAIL)',text,re.M),(name,text[-15000:])
 q['status']='PASS';save();print(name+' PASS',flush=True)
try:
 consumed=verify();r.update(js06_receipt_sha256=consumed['js06_receipt_sha256'],native04_receipt_sha256=consumed['native04_receipt_sha256'],retained_bend_paths=consumed['retained_bend_paths'],retained_bend_source_gate=consumed['source_gate_317878'],retained_service=consumed['unchanged_genuine_service_artifact']);save()
 run('native-source66',['node','test/tools/native_thin_bridge_307265.mjs'])
 run('native-rows12',['node','test/tools/native_thin_rows_307265.mjs'])
 run('native-privacy10',['node','test/tools/native_thin_privacy_307265.mjs'])
 run('native-engine-source-boundaries',['python3','test/phone-cache/thin/check_paging_successor.py'])
 assert not (out/'bridge-start.json').exists(),'Prior emission effects need reconciliation; never blindly re-emit'
 (out/'bridge-start.json').write_text(json.dumps({'at':time.time(),'entry':'src/mobile/app.bend','reason':'Actual07 info frames incorrectly failed current native presentation; consumeexact052007 ancillary/latch/owe/epoch fix'},indent=2)+'\n')
 run('mobile-bridge-emission',['bash','scripts/build-mobile.sh','--js'],timeout=600)
 run('legacy-mailroom138',['bun','test/tools/ios_mailroom_bridge_test.ts','mobile/build/assets/bridge.js',str(out/'legacy-mailroom.json')])
 run('actual-production41',['bun','test/tools/native_thin_emitted_307265.mjs','mobile/build/assets/bridge.js','test/fixtures/thin_saved_wire_315468.json'])
 run('actual07-ordered-replay',['node','test/tools/native_thin_actual07_307265.mjs','mobile/build/assets/bridge.js','test/fixtures/native-thin-actual07-307265.json'])
 verify();r.update(status='PASS_AFFECTED_ACTUAL_NATIVE_BRIDGE_ONLY',bridge_sha256=h('mobile/build/assets/bridge.js'),bridge_bytes=Path('mobile/build/assets/bridge.js').stat().st_size,end=time.time())
except BaseException as e:r.update(status='FAIL',error=repr(e));save();raise
save();print(json.dumps(r,indent=2))
