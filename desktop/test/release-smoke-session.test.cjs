'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),{EventEmitter}=require('node:events');
const {windowAuthWitness,cleanupOwnedUi,childAlive}=require('./release-smoke.cjs');
function fixture(cookies,{sameSession=true,url='http://127.0.0.1:45678/',count=1}={}){
 const calls=[],ses={cookies:{get:async query=>{calls.push(query);return cookies;}}};
 return {calls,electron:{session:{fromPartition:partition=>{assert.equal(partition,'persist:backplane-ui');return sameSession?ses:{};}},BrowserWindow:{getAllWindows:()=>Array.from({length:count},()=>({webContents:{getURL:()=>url,session:ses}}))}}};
}
test('actual window session cookie proof is value-free and ignores default context',async()=>{
 const f=fixture([{name:'bp_token',value:'DO_NOT_RETURN',httpOnly:true}]);
 const witness=await windowAuthWitness(f.electron,'http://127.0.0.1:45678');
 assert.deepEqual(witness,{matchingWindows:1,uiPartition:true,cookieCount:1,httpOnly:true});
 assert.deepEqual(f.calls,[{url:'http://127.0.0.1:45678',name:'bp_token'}]);assert(!JSON.stringify(witness).includes('DO_NOT_RETURN'));
});
test('missing/insecure/ambiguous cookies and wrong window/partition remain refusals',async()=>{
 for(const [cookies,httpOnly] of [[[],false],[[{httpOnly:false}],false],[[{httpOnly:true},{httpOnly:true}],false]]){
  const f=fixture(cookies),w=await windowAuthWitness(f.electron,'http://127.0.0.1:45678');assert.equal(w.httpOnly,httpOnly);assert.equal(w.cookieCount,cookies.length);
 }
 const other=fixture([{httpOnly:true}],{sameSession:false});assert.equal((await windowAuthWitness(other.electron,'http://127.0.0.1:45678')).uiPartition,false);
 for(const options of [{url:'https://foreign.invalid/'},{count:2}]){const f=fixture([{httpOnly:true}],options),w=await windowAuthWitness(f.electron,'http://127.0.0.1:45678');assert.equal(w.httpOnly,false);assert.equal(f.calls.length,0);}
});
function child(){const c=new EventEmitter();c.exitCode=null;c.signalCode=null;c.kill=signal=>{c.signalCode=signal;queueMicrotask(()=>c.emit('exit',null,signal));return true;};return c;}
test('disposed Playwright app uses captured native child and retains cleanup error',async()=>{
 const c=child(),app={close:async()=>{throw Error('adapter already disposed');},process:()=>{throw Error('must never access disposed adapter');}};
 const r=await cleanupOwnedUi(app,c);assert.deepEqual(r,{closed:true,error:'adapter already disposed'});assert.equal(c.signalCode,'SIGTERM');assert.equal(childAlive(c),false);
});
test('normal cleanup and already exited captured child need no fallback',async()=>{
 const c=child();let killed=false;c.kill=()=>{killed=true;};const app={close:async()=>{c.exitCode=0;}};
 assert.deepEqual(await cleanupOwnedUi(app,c),{closed:true,error:undefined});assert.equal(killed,false);
 c.exitCode=null;c.signalCode='SIGTERM';assert.equal(childAlive(c),false);
});
