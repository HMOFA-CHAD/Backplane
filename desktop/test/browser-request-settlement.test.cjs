'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{createHash}=require('node:crypto');
const {createDesktopBrowserController}=require('../browser-controller.cjs');
const {LIMITS}=require('../browser-envelope.cjs');
const {createBrowserUnknownState}=require('../browser-dispatch.cjs');
const tick=()=>new Promise(resolve=>setImmediate(resolve));
async function fixture(reply){
 let receive,sequence=0,closed=0,guestCalls=0;
 const sent=[],identity={serviceEpoch:'a'.repeat(32),controllerLease:'b'.repeat(32)};
 const deliver=(op,id,payload,extra={})=>receive({v:1,op,id,...identity,serverSequence:++sequence,payload,...extra});
 const controller=createDesktopBrowserController({electron:{},window:{},appSession:{},origin:'http://127.0.0.1:40001',version:'fixture',token:'c'.repeat(32),
  guestManagerSha256:createHash('sha256').update(fs.readFileSync(path.join(__dirname,'../browser-guest.cjs'))).digest('hex'),recorder:{},unknownState:createBrowserUnknownState(),executeCall:async()=>{guestCalls++;},
  channelFactory:async options=>{receive=options.onMessage;return{send(message){sent.push(message);if(message.op==='hello')queueMicrotask(()=>deliver('hello.accept',message.id,{protocol:1,version:'fixture',hub:'fixture',...identity,limits:{...LIMITS}}));else if(message.op==='owner.request')queueMicrotask(()=>reply({message,deliver}));},close(){closed++;}};},
  managerFactory:()=>({reconcileInput(){},dispose(){},list(){return[];}}),surfaceFactory:()=>({present(){guestCalls++;return{shown:false};},hide(){},dispose(){}})});
 await controller.start();assert.equal(controller.state().phase,'ready');
 return{controller,sent,deliver,identity,get closed(){return closed;},get guestCalls(){return guestCalls;}};
}
test('a correlated owner rejection settles immediately without closing the healthy controller or invoking a guest',async()=>{
 const h=await fixture(({message,deliver})=>deliver('result',message.id,{ok:false,error:'unknown canonical browser owner',dispatched:false}));
 try{
  const p=h.controller.present({owner:'retired-owner',bounds:{x:0,y:0,width:100,height:100}});
  const result=await Promise.race([p.then(()=>({resolved:true}),error=>({error})),new Promise(resolve=>setTimeout(()=>resolve({timedOut:true}),80))]);
  assert(!result.timedOut,'explicit error was left pending until the acknowledgement deadline');assert.match(result.error?.message||'',/Browser service refused request/);assert.equal(result.error.dispatched,false);
  assert.equal(h.controller.isClosed(),false);assert.equal(h.closed,0);assert.equal(h.guestCalls,0);assert.equal(h.sent.filter(x=>x.op==='owner.request').length,1);
 }finally{h.controller.close();}
});

function present(h,owner='fixture-owner'){return h.controller.present({owner,bounds:{x:0,y:0,width:100,height:100}});}
function grant(h,id,owner='fixture-owner'){h.deliver('owner.grant',id,{owner,revision:1,ttlMs:3000,operations:['list']});}
test('a refused owner does not prevent a subsequent explicit request for a valid owner',async()=>{
 let count=0;const h=await fixture(({message,deliver})=>{if(++count===1)deliver('result',message.id,{ok:false,error:'refused',dispatched:false});else deliver('owner.grant',message.id,{owner:message.payload.owner,revision:1,ttlMs:3000,operations:['list']});});
 try{await assert.rejects(present(h,'retired-owner'),{dispatched:false});const r=await present(h,'fixture-owner');assert.equal(r.shown,false);assert.equal(h.controller.isClosed(),false);assert.equal(count,2);assert(h.guestCalls>=1);}finally{h.controller.close();}
});
test('a foreign-id refusal cannot settle a pending owner request',async()=>{
 let request;const h=await fixture(({message,deliver})=>{request=message;deliver('result','d'.repeat(32),{ok:false,error:'foreign',dispatched:false});});
 try{let settled=false;const p=present(h).finally(()=>{settled=true});await tick();assert.equal(settled,false);assert.equal(h.guestCalls,0);grant(h,request.id);await p;assert.equal(settled,true);assert.equal(h.controller.isClosed(),false);}finally{h.controller.close();}
});
test('an ordinary success cannot substitute for the requested owner grant',async()=>{
 let request;const h=await fixture(({message,deliver})=>{request=message;deliver('result',message.id,{ok:true});});
 try{let settled=false;const p=present(h).finally(()=>{settled=true});await tick();assert.equal(settled,false);assert.equal(h.guestCalls,0);grant(h,request.id);await p;assert.equal(h.controller.isClosed(),false);}finally{h.controller.close();}
});
test('a late duplicate rejection cannot settle a different pending request',async()=>{
 const requests=[];const h=await fixture(({message})=>requests.push(message));
 try{
  const first=present(h,'old-owner');await tick();h.deliver('result',requests[0].id,{ok:false,error:'refused',dispatched:false});await assert.rejects(first,{dispatched:false});
  let settled=false;const next=present(h).finally(()=>{settled=true});await tick();h.deliver('result',requests[0].id,{ok:false,error:'late',dispatched:false});await tick();assert.equal(settled,false);assert.equal(h.guestCalls,0);
  grant(h,requests[1].id);await next;assert.equal(h.sent.filter(x=>x.op==='owner.request').length,2);assert.equal(h.controller.isClosed(),false);
 }finally{h.controller.close();}
});
test('a rejection from a stale service epoch is refused before request settlement',async()=>{
 let request;const h=await fixture(({message})=>{request=message;});
 try{let settled=false;const p=present(h).catch(()=>{}).finally(()=>{settled=true});await tick();assert.throws(()=>h.deliver('result',request.id,{ok:false},{serviceEpoch:'e'.repeat(32)}),/Stale/);await tick();assert.equal(settled,false);assert.equal(h.guestCalls,0);h.controller.close();await p;}finally{h.controller.close();}
});
