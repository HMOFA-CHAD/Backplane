'use strict';
// Consumes the backend owner's actual SERVICE component or original Windows
// resource ZIP. Assembly only: no runtime collector, emitter or compiler here.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const p=require('./produce-release.cjs');
const WINDOWS='1c12bd80b6f994ecd0d68d06b8ada98e1958de725d33f6380da3c0243ad099e3';
const ref=file=>({path:path.resolve(file),sha256:p.digest(file),bytes:fs.statSync(file).size});
function options(argv){
  const keys=['--components','--service','--freeze','--out'];assert.equal(argv.length,keys.length*2,'Expected '+keys.join(', '));
  const a={};for(let i=0;i<argv.length;i+=2){assert(keys.includes(argv[i])&&!a[argv[i]],'Unknown/duplicate argument');assert(path.isAbsolute(argv[i+1]),'Absolute paths required');a[argv[i]]=argv[i+1];}return a;
}
function component(spec,file){
  return {receipt:ref(p.reference(spec.receipt)),payload:{directory:path.resolve(path.dirname(file),spec.payload.directory)}};
}
function stage(a){
  const file=a['--components'],components=p.json(file),freeze=p.json(a['--freeze']),out=a['--out'];
  assert.equal(components.kind,'backplane-desktop-prepared-components');assert(p.TARGETS[components.target],'Unknown target');
  assert(!fs.existsSync(out)&&!fs.existsSync(out+'.request.json'),'Output/request exists');
  assert.equal(freeze.commit,components.release.commit);assert.equal(freeze.tree,components.release.tree);
  const service=components.target==='windows-x64'?{archive:ref(a['--service']),contractSha256:WINDOWS}:
    {receipt:ref(a['--service']),payload:{directory:path.join(path.dirname(a['--service']),'payload')}};
  const request={schema:1,kind:'backplane-electron-release-inputs',target:components.target,
    release:{...components.release,freezeReceipt:ref(a['--freeze'])},shell:component(components.shell,file),electron:component(components.electron,file),service};
  p.write(out+'.request.json',request);return p.stage(out+'.request.json',out);
}
function main(argv){
  if(argv.length===1&&argv[0]==='--help'){console.log('node desktop/prepare-native-stage.cjs stage --components ABS_COMPONENT_INPUTS_JSON --service ABS_BACKEND_SERVICE_JSON_OR_ORIGINAL_WINDOWS_RESOURCE_ZIP --freeze ABS_ROOT_FREEZE_JSON --out NEW_ABS_STAGE\nUse SERVICE.json/payload from113244 actual native factory on Unix; original1c12 resourceZIP from177217 on Windows. No measurement/compiler/payload execution; output stays STAGED_UNQUALIFIED.');return;}
  assert.equal(argv[0],'stage','Only stage is supported');console.log(JSON.stringify(stage(options(argv.slice(1))),null,2));
}
module.exports={options,component,stage};
if(require.main===module)try{main(process.argv.slice(2));}catch(e){console.error('Native desktop staging: '+e.message);process.exitCode=1;}
