'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {sanitize}=require('../connection-record.cjs');
const keys=['$','t','id','m','p','ok'],words=['MessagePosted','TurnChanged','ActivityLogged','changes','delta','reply'];
const text=s=>[0x60+s.length,...Buffer.from(s)],meta=()=>import('../../src/web/frame-summary.js');
test('rejected envelope metadata separates ordinary and thin replies without reading their payload',async()=>{
 const {frameSummary}=await meta();
 const ordinary=Uint8Array.from([0xa4,1,0xc6,5,2,0x18,42,5,0xf5,...text('result'),0x7a,0,0x12,0x65,0x17]);
 assert.deepEqual(frameSummary(ordinary,keys,words),{frameType:'reply',frameClass:'ordinary-reply'});
 const view=Uint8Array.from([0xa4,1,0xc6,5,2,0xc7,...text(String(2**47)),5,0xf5,...text('result'),0x7a,0,0x12,0x65,0x17]);
 assert.deepEqual(frameSummary(view,keys,words),{frameType:'reply',frameClass:'view-reply'});
 const prefix=[0xa3,1,...text('plot'),...text('mesh')];let highest=-1;
 const guarded=new Proxy({length:1205527},{get(o,k){if(k==='length')return o.length;const n=Number(k);if(!Number.isInteger(n))return undefined;highest=Math.max(highest,n);assert(n<prefix.length,'must stop before body');return prefix[n];}});
 assert.deepEqual(frameSummary(guarded,keys,words),{frameType:'plot',frameClass:'notification'});assert(highest<prefix.length);
});
test('malformed or private headers stay bounded and never become diagnostic text',async()=>{
 const {frameSummary}=await meta();
 for(const bytes of [[],[0xa1,1,0x7a,255,255,255,255],[0xa1,1,...text('PRIVATE token prompt')],[0xbf]]) {
  const r=frameSummary(Uint8Array.from(bytes),keys,words);assert.deepEqual(r,{frameType:'unknown',frameClass:'unknown'});assert(!JSON.stringify(r).includes('PRIVATE'));
 }
});
test('native record accepts only fixed frame enums and discards arbitrary text and payloads',()=>{
 assert.deepEqual(sanitize({event:'error',cause:'frame-limit',lastFrameBytes:1205527,frameType:'reply',frameClass:'ordinary-reply',payload:'PRIVATE'}),
  {event:'error',lastFrameBytes:1205527,cause:'frame-limit',frameType:'reply',frameClass:'ordinary-reply'});
 const secret='https://private.invalid/?token=PRIVATE prompt';const r=sanitize({event:'error',frameType:secret,frameClass:secret,payload:secret});assert.deepEqual(r,{event:'error'});
});
