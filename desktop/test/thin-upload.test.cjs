'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
async function fixture(){
 const {ThinHost,preservePresentationRoute,presentationTarget}=await import('../../src/web/thin-host.js'),{ThinViews,VIEW_LIMITS}=await import('../../src/web/thin.js');
 const source=fs.readFileSync(process.env.HOST_UPLOAD_SOURCE||path.resolve(__dirname,'../../src/web/host.js'),'utf8');
 let a=source.indexOf('function uploadScope(');if(a<0)a=source.indexOf('async function upload(');const b=source.indexOf('document.addEventListener("change",',a);
 const requests=[],sent=[],completions=[],commands=[];
 let session={sel:'A',rid:1,drafts:{A:'kept 日本語',B:'other draft'},open:{},info:{},outbox:{},route:{kind:'bot-tab',bot:'b',tab:'chat'}};
 const ctx={crypto:globalThis.crypto,Uint8Array,Array,JSON,URLSearchParams,viewMode:'view-v1',remoteReady:true,ui:session,
  App:{sel:u=>u.sel,uploading:(u,t)=>u.drafts['@att.up:'+t]||'',act:(u,action,value)=>{const r=JSON.parse(value);return{ui:{...u,drafts:{...u.drafts,['@att:'+r.thread]:r.attached}},cmds:null};},presentation:u=>{const {route,...plain}=u;return plain;}},
  Wire:{plain:x=>x},run(){},later(){},dispatch(){throw Error('unexpected legacy action');},currentSession:()=>session,
  fetch:(url,options)=>new Promise(resolve=>requests.push({url,options,complete:answer=>resolve({text:async()=>JSON.stringify(answer)})}))};
 const choice=(s,a,v)=>a==='select'?{...s,sel:v,route:undefined}:a==='draft'?{...s,drafts:{...s.drafts,[s.sel]:v}}:s;
 const api={hub:'https://fixture',cid:'upload-fixture',now:()=>0,session:()=>session,target:presentationTarget,choice,
  prepare:s=>preservePresentationRoute(s,{...s,rid:s.rid}),counter(){},send:r=>sent.push(structuredClone(r)),local(){},
  sessionChanged:s=>{session=s;ctx.ui=s;},ack:s=>s,decode:n=>n,command:c=>commands.push(c),state(){},view(){},anchor:()=>({id:'',offset:0}),blocked(){},warning(){}};
 const host=new ThinHost(api,ThinViews,2**47);ctx.thin=host;vm.createContext(ctx);vm.runInContext(source.slice(a,b),ctx);
 const reply=(request=sent.at(-1),extra={})=>({t:'reply',id:request.id,ok:true,result:{version:1,hub:api.hub,generation:'7',epoch:'e',requestRevision:request.p.requestRevision,target:request.p.target,viewId:request.p.viewId||'view',viewRevision:'1',remoteReady:true,renderer:'web',shown:{type:'text',text:'current'},session:structuredClone(session),cmds:[],window:{ids:[],older:'',hasMore:false,anchor:{id:'',offset:0},partial:[]},...extra}});
 host.greeting({t:'view',version:1,renderer:'web',generation:'7',epoch:'e',limits:{...VIEW_LIMITS}});host.receive(reply());
 const settle=()=>new Promise(r=>setImmediate(r));
 const admit=async(name,accepted=true)=>{const request=sent.at(-1);assert.equal(request.p.action,'attach-up');const updated={...session,drafts:{...session.drafts,...(accepted?{['@att.up:'+session.sel]:name}:{})}};host.receive(reply(request,{session:updated}));await settle();};
 const finish=async(index,answer)=>{requests[index].complete(answer);await settle();const request=sent.at(-1);if(request.p.action==='attach-end'){const o=JSON.parse(request.p.value);completions.push(o);const drafts={...session.drafts,['@att.up:'+o.thread]:''};if(o.attached)drafts['@att:'+o.thread]=[drafts['@att:'+o.thread],o.attached].filter(Boolean).join('\n');host.receive(reply(request,{session:{...session,drafts}}));await settle();}};
 const file=name=>({name,type:'image/png',size:3,body:'bytes:'+name});
 return{ctx,host,requests,sent,commands,completions,admit,finish,reply,settle,file,getSession:()=>session,start:name=>ctx.upload('attach',file(name)),batch:names=>ctx.uploadFiles('attach',names.map(file))};
}
test('HTTP completion uses correlated attach-end, preserves Chat route and leaves attachment authority in the actor',{timeout:1000},async()=>{
 const f=await fixture(),p=f.start('first.png');assert.equal(f.requests.length,0);await f.admit('first.png');assert.equal(f.requests.length,1);
 await f.finish(0,{thread:'A',attached:'/A/first.png'});await p;
 assert.equal(f.completions.length,1);assert.equal(f.getSession().drafts['@att:A'],'/A/first.png');assert.equal(f.getSession().route.tab,'chat');assert.equal(f.getSession().drafts.A,'kept 日本語');assert.equal(f.commands.length,0);
});
test('refused actor admission never sends a file body',{timeout:1000},async()=>{
 const f=await fixture(),p=f.start('too-large.png');await f.admit('too-large.png',false);await p;assert.equal(f.requests.length,0);
});
test('two selected PNGs are sequential, keep exact bodies and each settle once in the original actor',{timeout:1000},async()=>{
 const f=await fixture(),p=f.batch(['one.png','two.png']);await f.admit('one.png');assert.equal(f.requests.length,1);
 await f.finish(0,{thread:'A',attached:'/A/one.png'});await f.admit('two.png');assert.equal(f.requests.length,2);
 await f.finish(1,{thread:'A',attached:'/A/two.png'});await p;
 assert.deepEqual(f.requests.map(r=>new URL(r.url,'https://fixture').searchParams.get('thread')),['A','A']);
 assert.deepEqual(f.requests.map(r=>r.options.body.body),['bytes:one.png','bytes:two.png']);
 assert.equal(f.getSession().drafts['@att:A'],'/A/one.png\n/A/two.png');assert.equal(f.getSession().route.tab,'chat');assert.equal(f.getSession().drafts.B,'other draft');assert.equal(f.completions.length,2);
});
test('navigation retires old HTTP completion and remaining batch without retargeting or erasing newer empty draft',{timeout:1000},async()=>{
 const f=await fixture(),p=f.batch(['one.png','two.png']);await f.admit('one.png');f.host.request('select','B');f.host.receive(f.reply());f.host.request('draft','');
 await f.finish(0,{thread:'A',attached:'/A/one.png'});await p;
 assert.equal(f.requests.length,1);assert.equal(f.completions.length,0);assert.equal(f.getSession().sel,'B');assert.equal(f.getSession().drafts.B,'');assert.equal(f.getSession().drafts['@att:B'],undefined);
});
test('replacement controller and mismatched HTTP owner cannot receive old upload completion',{timeout:1000},async()=>{
 const f=await fixture(),p=f.start('one.png');await f.admit('one.png');f.ctx.thin={};await f.finish(0,{thread:'A',attached:'/A/one.png'});await p;assert.equal(f.completions.length,0);
 const g=await fixture(),q=g.start('one.png');await g.admit('one.png');await g.finish(0,{thread:'B',attached:'/B/wrong.png'});await q;assert.equal(g.completions.length,0);
});
