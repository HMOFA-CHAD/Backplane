'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const load=()=>import('../../src/web/replay.js');
test('yields without reordering or duplicating frames and completes before connect',async()=>{
 const {replayFrames}=await load(),seen=[],turns=[];let clock=0,connected=false;
 await replayFrames([1,2,3,4,5],n=>{assert(!connected);seen.push(n);clock+=5;},{now:()=>clock,yieldTask:async()=>{turns.push([...seen]);assert(!connected);}});
 connected=true;assert.deepEqual(seen,[1,2,3,4,5]);assert.deepEqual(turns,[[1,2],[1,2,3,4]]);
});
test('waits for the yielded task before applying later frames',async()=>{
 const {replayFrames}=await load(),seen=[];let release,clock=0;
 const pending=replayFrames([1,2],n=>{seen.push(n);clock+=10;},{now:()=>clock,yieldTask:()=>new Promise(r=>release=r)});
 assert.deepEqual(seen,[1]);release();await pending;assert.deepEqual(seen,[1,2]);
});
test('propagates corrupt-frame failure and never applies later frames',async()=>{
 const {replayFrames}=await load(),seen=[];
 await assert.rejects(replayFrames([1,2,3],n=>{if(n===2)throw Error('bad frame');seen.push(n);}),/bad frame/);assert.deepEqual(seen,[1]);
});
test('an empty cache completes without a scheduled task',async()=>{
 const {replayFrames}=await load();await replayFrames([],()=>assert.fail(),{yieldTask:()=>assert.fail()});
});
test('the default browser task yield lets other queued work run',async()=>{
 const {replayFrames}=await load(),seen=[];let clock=0;
 const pending=replayFrames([1,2],n=>{seen.push(n);clock+=10;},{now:()=>clock});queueMicrotask(()=>seen.push('input'));await pending;assert.deepEqual(seen,[1,'input',2]);
});
test('a late cache read after its deadline never applies a frame',async()=>{
 const {restoreCache}=await load();let resolve;const seen=[];
 const result=await restoreCache(()=>new Promise(r=>resolve=r),n=>seen.push(n),{timeoutMs:5});
 assert.equal(result.applied,0);assert(result.error);resolve([1,2]);await Promise.resolve();assert.deepEqual(seen,[]);
});
test('cache timeout waits for an in-progress yield to quiesce before handoff',async()=>{
 const {restoreCache}=await load();let release,finished=false,clock=0;const seen=[];
 const pending=restoreCache(async()=>[1,2,3],n=>{seen.push(n);clock+=10;},{timeoutMs:5,now:()=>clock,yieldTask:()=>new Promise(r=>release=r)}).then(r=>{finished=true;return r;});
 await new Promise(r=>setTimeout(r,10));assert(!finished);assert.deepEqual(seen,[1]);release();const result=await pending;assert(result.error);assert.equal(result.applied,1);assert.deepEqual(seen,[1]);
});
test('corrupt cache retains only the fully applied prefix for actual resume',async()=>{
 const {restoreCache}=await load();let cursor=0;
 const result=await restoreCache(async()=>[3,'bad',9],frame=>{if(frame==='bad')throw Error('corrupt');cursor=frame;});
 assert.equal(result.applied,1);assert.equal(cursor,3);assert.match(result.error.message,/corrupt/);
});
