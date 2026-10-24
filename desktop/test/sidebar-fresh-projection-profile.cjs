// Exact candidate pure functions; synthetic state only, no live store/service.
const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {performance}=require('node:perf_hooks');
function engine(file,sourceCommit,stamped){
const source=fs.readFileSync(file,'utf8'),defs=new Map();
for(const m of source.matchAll(/^function ([\w$]+)\([^\n]*\) \{[\s\S]*?^\}$/gm))defs.set(m[1],m[0]);
const root=tail=>{const a=[...defs.keys()].filter(n=>n.endsWith(tail));assert.equal(a.length,1,tail);return a[0]};
const names={empty:root('core$047model$058State$empty$'),apply:root('core$047model$058State$apply$'),index:root('core$047thin$058Index$empty$'),stream:root('core$047thin$045live$058Stream$blank$'),refresh:root('thin$045actor$058Actor$refresh$'),render:root('thin$045actor$058Actor$render$'),show:root('core$047json$058Json$show$'),encode:root('core$047cbor$058Cbor$encode$'),encText:root('core$047cbor$058Enc$text$'),encHead:root('core$047cbor$058Enc$head$'),output:root('thin$045sidebar$045wire$058Region$output$'),sidebar:root('web$047sidebar$045slot$058Slot$sidebar$')};
const needed=new Set(),todo=Object.values(names);while(todo.length){const n=todo.pop();if(needed.has(n))continue;needed.add(n);for(const m of defs.get(n).matchAll(/[A-Za-z_$][\w$]*/g))if(defs.has(m[0])&&!needed.has(m[0]))todo.push(m[0]);}
const ctx=vm.createContext({});vm.runInContext([...needed].map(n=>defs.get(n)).join('\n')+'\nglobalThis.f={'+Object.entries(names).map(([k,n])=>k+':'+n).join(',')+'};',ctx,{timeout:10000});
const helper=fs.readFileSync(path.join(__dirname,'../../scripts/js-cbor-text.js'),'utf8'),native=fs.readFileSync(stamped,'utf8');assert(native.includes(helper));assert(native.includes('function '+names.encText+'(_s_0,_acc_0){return __bpCborText(_s_0,_acc_0,'+names.encHead+');'));
vm.runInContext(helper+';'+names.encText+'=(s,a)=>__bpCborText(s,a,'+names.encHead+');',ctx);
function json(v){if(v===null)return {$:'../core/json.Null'};if(typeof v==='string')return {$:'../core/json.Str',text:v};if(typeof v==='boolean')return {$:'../core/json.Flag',value:v};if(typeof v==='number')return {$:'../core/json.Num',raw:String(v)};if(Array.isArray(v)){let items={$:'../core/json.End'};for(const x of [...v].reverse())items={$:'../core/json.Item',head:json(x),tail:items};return {$:'../core/json.Arr',items};}let fields={$:'../core/json.End'};for(const [key,value]of Object.entries(v).reverse())fields={$:'../core/json.Field',key,value:json(value),tail:fields};return {$:'../core/json.Obj',fields};}
const plain=v=>JSON.parse(ctx.f.show(v));
function bytes(xs){const a=[];for(let x=xs;x.$!=='Nil';x=x.tail)a.push(x.head);return Uint8Array.from(a)}
function measure(fn){const t=performance.now(),value=fn();return {value,ms:performance.now()-t}}

function get(o,key){for(let f=o.fields;f&&f.$.endsWith('.Field');f=f.tail)if(f.key===key)return f.value;throw Error('Missing Json field '+key)}
const counts={};ctx.recordProjection=(tail,old,args)=>{const at=performance.now();try{return old(...args)}finally{const r=counts[tail]||(counts[tail]={calls:0,inclusiveMs:0});r.calls++;r.inclusiveMs+=performance.now()-at}};
for(const tail of ['core$047client$058Side$rows$ix$','core$047client$058Active$rows$ix$','web$047view$058View$sidebar$']){
 const n=root(tail);vm.runInContext(n+'=((old)=>(...args)=>recordProjection('+JSON.stringify(tail)+',old,args))('+n+');',ctx);
}
return {ctx,json,plain,bytes,counts,sourceCommit,emitSha256:crypto.createHash('sha256').update(source).digest('hex'),nativeSha256:crypto.createHash('sha256').update(native).digest('hex')};
}
const [out,beforeFile,beforeCommit,beforeNative,afterFile,afterCommit,afterNative]=process.argv.slice(2);
assert(out&&afterNative);
const baselineControl=process.env.FRESH_BASELINE_CONTROL==='1';
const nil={$:'Nil'},now=1792800000,rows=[];
const before=engine(beforeFile,beforeCommit,beforeNative),after=engine(afterFile,afterCommit,afterNative);
function timed(fn){const t=performance.now(),value=fn();return {value,ms:performance.now()-t}}
function prepare(e,shape){
 const {ctx,json,plain,bytes,counts}=e;
 let st=ctx.f.empty();for(let p=0;p<45;p++)st=ctx.f.apply(st,{$:'../core/model.ProjectCreated',id:'p'+p,title:'Synthetic project '+p,root:'/tmp/fresh-shelves-'+p,at:now-3600});
 for(let i=0;i<2786;i++){
  st=ctx.f.apply(st,{$:'../core/model.ThreadCreated',id:'t'+i,project:'p'+i%45,title:'Synthetic thread '+i,env:{$:'../core/model.Local'},branch:'',worktree:'',provider:'codex',model:'',at:now-3600});
  if(i>=32)st=ctx.f.apply(st,{$:'../core/model.ThreadSettled',id:'t'+i,manual:false,at:now-3599});
  if(shape.nested&&i>=45&&i<90)st=ctx.f.apply(st,{$:'../core/model.ThreadParentSet',id:'t'+i,parent:'t'+(i%45),at:now-3598});
 }
 for(const [key,value]of [['onboard.done','1'],['sidebar.view',shape.mode]])st=ctx.f.apply(st,{$:'../core/model.SettingSet',key,value,at:now-3590});
 const info=json({models:JSON.stringify({codex:['gpt-6.1-sol'],claude:['opus']})}),live=json({}),p={target:{kind:'thread',id:'t0'},session:{sel:'t0',rid:100,open:{settings:true},drafts:{t0:'Synthetic draft'},info:{}},action:'settings-page',value:'appearance',requestRevision:1,sidebarRegion:{version:1,token:''}};
 const actor=ctx.f.refresh(nil,true,st,info,live,now,json(p),'synthetic'),first=ctx.f.render(actor,true,st,ctx.f.index(),json(p),'synthetic',now,nil,ctx.f.stream()),seed=ctx.f.output(true,{$:'Con',head:first.actor,tail:nil},first.result,json(p));
 return function sample(changed){
  const current=changed?ctx.f.apply(st,{$:'../core/model.ThreadSettled',id:'t1',manual:true,at:now+1}):st;
  const next={...p,requestRevision:2,sidebarRegion:{version:1,token:'1'}},a=ctx.f.refresh(seed.actors,true,current,info,live,now+1,json(next),'synthetic');
  for(const k of Object.keys(counts))delete counts[k];
  const render=timed(()=>ctx.f.render(a,true,current,ctx.f.index(),json(next),'synthetic',now+1,nil,ctx.f.stream()));
  const callCounts=structuredClone(counts);
  assert(callCounts['core$047client$058Side$rows$ix$']?.calls>0,'Actual VM counter must attach');
  const full=ctx.f.show(render.value.result),encoded=timed(()=>ctx.f.encode(render.value.result)),buffer=Buffer.from(bytes(encoded.value));
  const wire=plain(ctx.f.output(true,{$:'Con',head:render.value.actor,tail:nil},render.value.result,json(next)).result);assert.equal(wire.sidebarRegion.base,'','Clock/canonical change must retain full-reply guard');
  return {changed,renderMs:render.ms,callCounts,logicalSha256:crypto.createHash('sha256').update(full).digest('hex'),fullCborSha256:crypto.createHash('sha256').update(buffer).digest('hex'),fullLogicalChars:full.length,runtimeSizeEligible:full.length<=262144&&buffer.length<=262144,fullCborBytes:buffer.length,encodeMs:encoded.ms,clockMissSentFull:true};
 };
}
let state='passed';try{
 for(const shape of [{mode:'active',nested:false},{mode:'active',nested:true},{mode:'projects',nested:false}]){
  const b=prepare(before,shape),a=prepare(after,shape),negative={};
  for(const changed of [false,true])for(let pair=0;pair<4;pair++){
   let x,y;const order=pair%2?'after-before':'before-after';
   if(pair%2){y=a(changed);x=b(changed)}else{x=b(changed);y=a(changed)}
   assert.equal(y.logicalSha256,x.logicalSha256,'Complete logical reply must remain exact');assert.equal(y.fullCborSha256,x.fullCborSha256,'Complete transport bytes must remain exact');
   assert.equal(x.callCounts['core$047client$058Side$rows$ix$'].calls,shape.mode==='active'?3:1);
   assert.equal(y.callCounts['core$047client$058Side$rows$ix$'].calls,baselineControl&&shape.mode==='active'?3:1);
   negative[String(changed)]=y.logicalSha256;
   const row={threads:2786,projects:45,active:32,...shape,changed,pair,order,identicalReply:true,identicalCbor:true,before:x,after:y};rows.push(row);fs.appendFileSync(out+'.pairs.jsonl',JSON.stringify(row)+'\n');
  }
  assert.notEqual(negative.false,negative.true,'Canonical negative control must change reply');
 }
}catch(e){state='failed';rows.push({error:e.stack})}
const binding=e=>({sourceCommit:e.sourceCommit,emitSha256:e.emitSha256,nativeSha256:e.nativeSha256});
const median=xs=>{const a=[...xs].sort((a,b)=>a-b);return (a[(a.length-1)>>1]+a[a.length>>1])/2};
const summaries=[];if(state==='passed')for(const mode of ['active','projects'])for(const nested of (mode==='active'?[false,true]:[false]))for(const changed of [false,true]){const rs=rows.filter(r=>r.mode===mode&&r.nested===nested&&r.changed===changed);summaries.push({mode,nested,changed,pairs:rs.length,beforeMedianRenderMs:median(rs.map(r=>r.before.renderMs)),afterMedianRenderMs:median(rs.map(r=>r.after.renderMs)),beforeMedianShelfMs:median(rs.map(r=>r.before.callCounts['core$047client$058Side$rows$ix$'].inclusiveMs)),afterMedianShelfMs:median(rs.map(r=>r.after.callCounts['core$047client$058Side$rows$ix$'].inclusiveMs)),beforeRenderRangeMs:[Math.min(...rs.map(r=>r.before.renderMs)),Math.max(...rs.map(r=>r.before.renderMs))],afterRenderRangeMs:[Math.min(...rs.map(r=>r.after.renderMs)),Math.max(...rs.map(r=>r.after.renderMs))]})}
const result={state,baselineControl,engine:{node:process.versions.node,bun:process.versions.bun||null,v8:process.versions.v8||null},summaries,before:binding(before),after:binding(after),rows,scope:'Four bounded alternating-order pairs per exact-emitted synthetic fresh-render shape; every raw timing retained with unchanged clock-miss and canonical-change negative controls, complete reply and native CBOR byte equality, actual projection counts. Same2786-thread/45-project/32-active inputs. Instrumented inclusive CPU is not live latency, INP or a live speedup claim. No service, UI, user history or provider invocation.'};fs.writeFileSync(out,JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));if(state!=='passed')process.exitCode=1;
