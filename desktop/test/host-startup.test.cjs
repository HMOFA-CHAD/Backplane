'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
// Execute the actual host connection adapter, with only platform/Bend IO
// replaced. This is a source integration check, not a service/Electron pass.
async function fixture(ready=false){
 const {FrontendStartup}=await import('../../src/web/startup.js');
 const source=fs.readFileSync(path.resolve(__dirname,'../../src/web/host.js'),'utf8');
 const a=source.indexOf('function connect() {'),b=source.indexOf('// when a frame (a heartbeat included)',a);assert(a>0&&b>a);
 let release,clock=0,next=0;const timers=new Map(),sockets=[],received=[];
 const later=[],live=[],sent=[];const encoder=new TextEncoder(),decoder=new TextDecoder();
 const setTimer=(fn,ms)=>{const id=++next;timers.set(id,{fn,at:clock+ms});return id;};
 class Startup extends FrontendStartup{constructor(api){super(api,{setTimer,clearTimer:id=>timers.delete(id)});}}
 class Socket{constructor(url){this.url=url;this.readyState=0;sockets.push(this);}open(){this.readyState=1;this.onopen();}send(bytes){sent.push({socket:this,request:JSON.parse(decoder.decode(bytes))});}frame(o){this.onmessage({data:encoder.encode(JSON.stringify(o)).buffer});}close(){this.readyState=3;this.onclose?.();}}
 const ctx={URLSearchParams,WebSocket:Socket,Uint8Array,BigInt,Number,JSON,Error,Math,location:{protocol:'http:',host:'fixture'},cid:'fixture',ui:{seq:0,origin:'',synced:false},
  socket:null,frontend:null,frontendNode:null,wantFrontend:true,fallbackIntent:null,cacheReady:ready,canonicalBoot:false,backoff:250,heard:0n,PERF:null,T:{Null:'Null'},KEYS:[],WORDS:[],
  restored:new Promise(r=>release=r),fromList:x=>x,trace(){},later:()=>later.push(true),laterLive:()=>live.push(true),setTimeout:setTimer,desktopBrowser:{hide(){}},Plot2d:{reset(){},got(){}},Solid:{isPlot:()=>false,reset(){},got(){}},restoreSubs(){},keep(){},run(){},
  document:{documentElement:{dataset:{}}},Wire:{plain:j=>j?.t==='reply'?{...j,id:j.id?.$==='Num'?Number(j.id.raw):j.id}:j,cbor:bytes=>JSON.parse(decoder.decode(bytes))},
  field:(j,k)=>j[k],jsonValue:(j,k)=>j[k]||{$:'Null'},is:(j,t)=>j.$===t,each:function*(xs){for(let x=xs;x?.$==='Con';x=x.tail)yield x.head;},
  presentationJson:x=>x,choosePresentation:(s,a,v)=>a==='select'?{...s,sel:v}:a==='draft'?{...s,drafts:{...s.drafts,[s.sel]:v}}:s,
  presentationCommand:c=>ctx.commandCalls.push(c),commandCalls:[],validatePresentation(){},adoptPresentation:s=>{ctx.ui={...ctx.ui,sel:s.sel,drafts:s.drafts};},performPresentation:o=>ctx.performed.push(o),performed:[],
  localPresentation:(a,v)=>{if(a==='select')ctx.ui={...ctx.ui,sel:v};},FrontendStartup:Startup};
 ctx.App={seq:u=>String(u.seq),origin:u=>u.origin,wire_out:s=>encoder.encode(s),unsync:u=>({...u,synced:false}),online:u=>u,kind:j=>j.t,part:(_u,j)=>j.t==='delta'?'live':'',
  recv:(u,j)=>{received.push(j);return{ui:{...u,seq:j.seq??u.seq,origin:j.origin??u.origin,synced:j.t==='log'&&j.complete===true||u.synced},cmds:{$:'Nil'}};},synced:u=>u.synced,
  presentation:()=>({sel:'A',drafts:{A:'draft'},rid:0}),presentation_allowed:a=>['select','draft','send'].includes(a),presentation_blocked:u=>u,
  presentation_prepare:s=>s,presentation_reply:s=>s,presentation_node:n=>n};
 vm.createContext(ctx);vm.runInContext(source.slice(a,b)+'\nconnect();',ctx);
 const settle=async(cursor={since:3,origin:'applied'})=>{ctx.ui={...ctx.ui,seq:cursor.since,origin:cursor.origin,synced:false};ctx.cacheReady=true;release();await Promise.resolve();await Promise.resolve();};
 return{ctx,sockets,sent,received,settle,release,later,live,tick:async ms=>{clock+=ms;for(const[id,t]of[...timers])if(t.at<=clock&&timers.has(id)){timers.delete(id);t.fn();}await Promise.resolve();await Promise.resolve();}};
}
test('actual host sends history when cache finished before socket opens',async()=>{
 const f=await fixture(true);await f.settle({since:21,origin:'cache'});const s=f.sockets[0];s.open();s.frame({t:'frontend',protocol:1,generation:'7'});
 const p=f.sent.find(x=>x.request.m==='frontend.history').request.p;assert.equal(p.since,21);assert.equal(p.origin,'cache');assert.equal(f.ctx.canonicalBoot,false);
});
test('actual host waits for cached fold and resumes its actual partial cursor on failure',async()=>{
 const f=await fixture();const s=f.sockets[0];s.open();s.frame({t:'frontend',protocol:1,generation:'7'});assert(!f.sent.some(x=>x.request.m==='frontend.history'));
 await f.settle({since:3,origin:'partial'});assert.equal(f.sent.find(x=>x.request.m==='frontend.history').request.p.since,3);assert.equal(f.received.length,0);
});
test('actual old-hub boot is buffered until cache writer stops, then applied once',async()=>{
 const f=await fixture();const s=f.sockets[0];s.open();s.frame({t:'log',since:0,seq:30,origin:'server',complete:true});assert.equal(f.received.length,0);
 await f.settle();assert.equal(f.received.length,1);assert.equal(f.ctx.ui.seq,30);assert.equal(f.ctx.canonicalBoot,true);assert(!f.sent.some(x=>x.request.m==='frontend.history'));
});
test('actual missing greeting reconnects legacy using applied cursor',async()=>{
 const f=await fixture();f.sockets[0].open();await f.tick(2000);assert.equal(f.ctx.wantFrontend,false);assert.equal(f.sockets.length,1);
 await f.settle({since:9,origin:'actual'});await f.tick(250);assert.equal(f.sockets.length,2);const url=new URL(f.sockets[1].url);assert.equal(url.searchParams.get('since'),'9');assert.equal(url.searchParams.has('frontend'),false);
});
test('actual late screen after canonical is intercepted without App.recv or command replay',async()=>{
 const f=await fixture(true);await f.settle();const s=f.sockets[0];s.open();s.frame({t:'frontend',protocol:1,generation:'7'});const screen=f.sent.find(x=>x.request.m==='frontend.screen').request;
 s.frame({t:'log',seq:40,origin:'server',complete:true});assert.equal(f.ctx.canonicalBoot,true);const received=f.received.length;
 s.frame({t:'reply',id:{$:'Num',raw:String(screen.id)},ok:true,result:{frontend:1,web:1,revision:screen.p.revision,session:{sel:'wrong',drafts:{},rid:4},view:{type:'text',text:'stale'},cmds:[{type:'send',text:'unwanted'}]}});
 assert.equal(f.received.length,received);assert.equal(f.ctx.commandCalls.length,0);assert.equal(f.ctx.ui.seq,40);assert.notEqual(f.ctx.ui.sel,'wrong');
});
test('actual info frame cannot claim canonical readiness after cache restore',async()=>{
 const f=await fixture(true);await f.settle();const s=f.sockets[0];s.open();s.frame({t:'info'});assert.equal(f.ctx.canonicalBoot,false);
});
test('actual rejected screen still starts history after cache failure settles',async()=>{
 const f=await fixture();const s=f.sockets[0];s.open();s.frame({t:'frontend',protocol:1,generation:'7'});const screen=f.sent.find(x=>x.request.m==='frontend.screen').request;
 s.frame({t:'reply',id:{$:'Num',raw:String(screen.id)},ok:false,error:'unavailable'});assert.equal(f.ctx.canonicalBoot,false);await f.settle({since:6,origin:'partial'});
 const histories=f.sent.filter(x=>x.request.m==='frontend.history');assert.equal(histories.length,1);assert.equal(histories[0].request.p.since,6);
});
test('actual canonical streaming retains the existing live-row render path',async()=>{
 const f=await fixture(true);await f.settle();const s=f.sockets[0];s.open();s.frame({t:'log',seq:40,complete:true});const full=f.later.length;
 s.frame({t:'delta'});assert.equal(f.live.length,1);assert.equal(f.later.length,full);
});
test('actual missing screen proceeds with the fully applied cursor before its deadline',async()=>{
 const f=await fixture();const s=f.sockets[0];s.open();s.frame({t:'frontend',protocol:1,generation:'7'});
 await f.settle({since:91,origin:'applied-epoch'});await f.tick(2000);
 const histories=f.sent.filter(x=>x.request.m==='frontend.history');assert.equal(histories.length,1);
 assert.deepEqual(JSON.parse(JSON.stringify(histories[0].request.p)),{generation:'7',since:91,origin:'applied-epoch'});
 assert.equal(f.ctx.frontend.phase,'history');assert.equal(f.ctx.canonicalBoot,false);assert.equal(f.ctx.ui.seq,91);
});
test('actual decoder failure retires the screen and starts history without dispatching its commands',async()=>{
 const f=await fixture();const s=f.sockets[0];s.open();s.frame({t:'frontend',protocol:1,generation:'7'});
 const screen=f.sent.find(x=>x.request.m==='frontend.screen').request;
 f.ctx.App.presentation_node=()=>{throw Error('invalid decoded tree');};
 const reply={t:'reply',id:{$:'Num',raw:String(screen.id)},ok:true,result:{frontend:1,web:1,revision:screen.p.revision,session:{sel:'wrong',drafts:{},rid:2},view:{},cmds:[{type:'send',text:'must not issue'}]}};
 s.frame(reply);await f.settle({since:0,origin:''});s.frame(reply);
 assert.equal(f.sent.filter(x=>x.request.m==='frontend.history').length,1);assert.equal(f.ctx.frontendNode,null);
 assert.equal(f.ctx.commandCalls.length,0);assert.equal(f.ctx.canonicalBoot,false);assert.equal(f.ctx.ui.seq,0);
});
test('actual missing history falls back once and late retired screens cannot escape into App.recv',async()=>{
 const f=await fixture(true);await f.settle({since:12,origin:'known'});const s=f.sockets[0];s.open();s.frame({t:'frontend',protocol:1,generation:'7'});
 const screen=f.sent.find(x=>x.request.m==='frontend.screen').request;await f.tick(5000);
 assert.equal(f.ctx.wantFrontend,false);assert.equal(f.ctx.canonicalBoot,false);assert.equal(f.received.length,0);
 assert(f.ctx.frontend.reply({id:screen.id,ok:true,result:{frontend:1,web:1,revision:screen.p.revision,session:{sel:'late',drafts:{},rid:2},view:{},cmds:[{type:'send',text:'never'}]}}));
 assert.equal(f.ctx.commandCalls.length,0);assert.equal(f.received.length,0);await f.tick(250);
 assert.equal(f.sockets.length,2);assert.equal(new URL(f.sockets[1].url).searchParams.get('since'),'12');
});
test('actual canonical-only rejection followed by canonical handoff retires a late presentation',async()=>{
 const f=await fixture(true);await f.settle();const s=f.sockets[0];s.open();s.frame({t:'frontend',protocol:1,generation:'7'});
 const screen=f.sent.find(x=>x.request.m==='frontend.screen').request;
 assert.equal(f.ctx.frontend.request('br-go','private'),true);assert.equal(f.ctx.frontend.waiting.length,0);
 s.frame({t:'log',seq:44,origin:'authoritative',complete:true});const count=f.received.length;
 s.frame({t:'reply',id:{$:'Num',raw:String(screen.id)},ok:true,result:{frontend:1,web:1,revision:screen.p.revision,session:{sel:'stale',drafts:{A:'stale'},rid:2},view:{},cmds:[{type:'send',text:'never'}]}});
 assert.equal(f.ctx.commandCalls.length,0);assert.equal(f.ctx.performed.length,0);assert.equal(f.received.length,count);
 assert.equal(f.ctx.ui.seq,44);assert.equal(f.ctx.canonicalBoot,true);assert.notEqual(f.ctx.ui.sel,'stale');
});
test('actual selection and draft overtake an older action reply without rendering or losing input',async()=>{
 const f=await fixture(true);await f.settle();const s=f.sockets[0];s.open();s.frame({t:'frontend',protocol:1,generation:'7'});
 f.ctx.frontend.request('send','');const action=f.sent.filter(x=>x.request.m==='frontend.screen').at(-1).request;
 f.ctx.frontend.request('select','B');f.ctx.frontend.request('draft','B newer 日本語');
 s.frame({t:'reply',id:{$:'Num',raw:String(action.id)},ok:true,result:{frontend:1,web:1,revision:action.p.revision,session:{sel:'A',drafts:{A:'older'},rid:5},view:{},cmds:[]}});
 assert.equal(f.ctx.frontendNode,null);assert.equal(f.ctx.frontend.session.sel,'B');assert.equal(f.ctx.frontend.session.drafts.B,'B newer 日本語');assert.equal(f.ctx.canonicalBoot,false);
});
test('actual host corrupt-cache continuation resets the cursor before history can read it',async()=>{
 const {restoreCache}=await import('../../src/web/replay.js');
 const source=fs.readFileSync(path.resolve(__dirname,'../../src/web/host.js'),'utf8');
 const a=source.indexOf('function restoreCompatibilityCache()'),b=source.indexOf('function jsonValue',a);assert(a>0&&b>a);
 for(const failure of ['read','decode']){
  const state={seq:99,origin:'must-reset',synced:true};let resets=0;
  const ctx={restoreCache,compatibilityRestore:null,openCompatibilityCache:()=>Promise.resolve(),db:{transaction:()=>({objectStore:()=>({getAll(){const r={};queueMicrotask(()=>failure==='read'?r.onerror():r.onsuccess());r.result=[new ArrayBuffer(1)];return r;}})})},FRAMES:'frames',
   Promise,Error,Uint8Array,ui:state,cid:'fixture',now:()=>0n,KEYS:[],WORDS:[],trace(){},cacheReady:false,restoreSubs(){},Wire:{cbor(){throw Error('invalid CBOR');}},
   App:{kind:()=> 'log',presentation_reset:()=>{resets++;return{seq:0,origin:'',synced:false};},unsync:u=>({...u,synced:false}),seq:u=>u.seq}};
  vm.createContext(ctx);vm.runInContext(source.slice(a,b)+'\nglobalThis.finished=restoreCompatibilityCache();',ctx);await ctx.finished;
  assert.equal(resets,1,failure);assert.equal(ctx.cacheReady,true);assert.equal(ctx.ui.seq,0);assert.equal(ctx.ui.origin,'');assert.equal(ctx.ui.synced,false);
  const host=await fixture();const s=host.sockets[0];s.open();s.frame({t:'frontend',protocol:1,generation:'7'});await host.settle({since:ctx.ui.seq,origin:ctx.ui.origin});
  const history=host.sent.find(x=>x.request.m==='frontend.history').request;assert.equal(history.p.since,0);assert.equal(history.p.origin,'');assert.equal(host.ctx.canonicalBoot,false);
 }
});
