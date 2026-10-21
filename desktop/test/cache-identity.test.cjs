'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const old='a'.repeat(64),next='b'.repeat(64);
async function fixture(initial=old){
 const {refreshCacheIdentity}=await import('../../src/web/cache-identity.js');let current=initial?`bp_cache_v1=${initial}`:'',calls=[],writes=[];
 const run=(fetch,extra={})=>refreshCacheIdentity({fetch:(url,o)=>{calls.push({url,o});return fetch(url,o);},readCookie:()=>current,writeCookie:value=>{writes.push(value);current=value.split(';')[0];},protocol:'https:',...extra});
 return{run,calls,writes,set:v=>current=`bp_cache_v1=${v}`,get:()=>current};
}
const jsonBody=text=>({status:200,headers:new Headers({'content-type':'application/json'}),body:new ReadableStream({start(c){c.enqueue(new TextEncoder().encode(text));c.close();}})});
const response=key=>jsonBody(JSON.stringify({version:1,cacheKey:key}));
test('an existing HttpOnly-paired profile bootstraps its public tag without re-pairing or a JS credential',async()=>{
 const f=await fixture('');assert.deepEqual(await f.run(async()=>response(old)),{state:'verified',identity:old});
 assert.equal(f.calls.length,1);assert.match(f.calls[0].url,/^\/auth\/cache\?bpProbe=[0-9a-f]{32}$/);assert.equal(f.calls[0].o.credentials,'same-origin');assert.equal(f.calls[0].o.cache,'no-store');assert.equal(f.calls[0].o.headers,undefined);assert(f.writes[0].includes('; Secure'));
});
test('rotation replaces the old namespace and never uses it as request authentication',async()=>{
 const f=await fixture();assert.equal((await f.run(async()=>response(next))).identity,next);assert(!JSON.stringify(f.calls).includes(old));
});
test('401 and 403 erase the marker and suppress old cache access',async()=>{
 for(const status of [401,403]){const f=await fixture();const r=await f.run(async()=>({status}));assert.equal(r.state,'denied');assert.equal(r.identity,'');assert(f.writes[0].includes('Max-Age=0'));}
});
test('offline failures retain only an existing readonly partition and do not invent one',async()=>{
 for(const initial of ['',old]){const f=await fixture(initial);assert.deepEqual(await f.run(async()=>{throw Error('offline');}),{state:'offline',identity:initial});assert.equal(f.writes.length,0);}
});
test('malformed, extra-field, wrong-version and oversized success responses suppress stale cache',async()=>{
 for(const body of ['{','{}',JSON.stringify({version:2,cacheKey:old}),JSON.stringify({version:1,cacheKey:old,token:'forbidden'}),' '.repeat(257)]){const f=await fixture();const r=await f.run(async()=>jsonBody(body));assert.equal(r.state,'invalid');assert.equal(r.identity,'');}
});
test('a newer profile marker overtakes the response without being overwritten',async()=>{
 const f=await fixture();let release;const p=f.run(()=>new Promise(r=>release=r));await Promise.resolve();f.set(next);release(response(old));const r=await p;assert.equal(r.state,'superseded');assert.equal(r.identity,next);assert.equal(f.writes.length,0);
});
test('a stalled fetch is bounded and its late response cannot write a marker',async()=>{
 const f=await fixture();let release;const result=await f.run(()=>new Promise(r=>release=r),{timeoutMs:5});assert.equal(result.state,'offline');release(response(next));await new Promise(r=>setImmediate(r));assert.equal(f.writes.length,0);assert.equal(f.get(),`bp_cache_v1=${old}`);
});
test('a stalled response body is also bounded and cannot overwrite on eventual completion',async()=>{
 const f=await fixture();let release;const result=await f.run(async()=>({status:200,headers:new Headers({'content-type':'application/json'}),body:new ReadableStream({start(c){release=text=>{c.enqueue(new TextEncoder().encode(text));c.close();};}})}),{timeoutMs:5});assert.equal(result.state,'offline');release(JSON.stringify({version:1,cacheKey:next}));await new Promise(r=>setImmediate(r));assert.equal(f.writes.length,0);
});
test('old service-worker HTML fallback is offline and cannot select another credential namespace',async()=>{
 const f=await fixture();const r=await f.run(async()=>({status:200,headers:new Headers({'content-type':'text/html'}),body:null}));assert.equal(r.state,'offline');assert.equal(r.identity,old);assert.equal(f.writes.length,0);
});
test('metadata probes are unique and contain neither credentials nor the public identity tag',async()=>{
 const f=await fixture();await f.run(async()=>response(old));await f.run(async()=>response(old));assert.notEqual(f.calls[0].url,f.calls[1].url);assert(!f.calls.some(c=>c.url.includes(old)));
});
