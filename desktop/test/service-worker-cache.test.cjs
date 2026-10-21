'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
function worker(){
 const source=fs.readFileSync(process.env.BP_SW_SOURCE||path.resolve(__dirname,'../../src/web/sw.js'),'utf8'),events=new Map(),cacheCalls=[];
 const cached=new Map([['/new-private-api',new Response('OLD PRIVATE RESPONSE')],['/',new Response('CACHED SHELL')]]);
 const ctx={self:{addEventListener:(name,fn)=>events.set(name,fn),skipWaiting(){},clients:{claim(){}}},location:{origin:'https://fixture'},URL,Response,
  fetch:async()=>{throw Error('offline');},caches:{open:async()=>{cacheCalls.push(true);return{match:async request=>cached.get(typeof request==='string'?request:new URL(request.url).pathname),put(){}};}}};
 vm.createContext(ctx);vm.runInContext(source,ctx);
 return{cacheCalls,cached,request:pathname=>{let response;events.get('fetch')({request:{url:'https://fixture'+pathname,method:'GET',cache:'default'},respondWith:p=>response=p});return response;},noStore:()=>{let response;events.get('fetch')({request:{url:'https://fixture/chunk-abc.js',method:'GET',cache:'no-store'},respondWith:p=>response=p});return response;}};
}
test('auth/capability/private data APIs never read the service-worker cache or root fallback',()=>{
 const w=worker();for(const p of ['/auth/cache','/auth/cache?bpProbe=random','/client/capabilities','/new-private-api','/hello','/bots/owner/screen.jpg','/view/file','/usage'])assert.equal(w.request(p),undefined,p);assert.equal(w.cacheCalls.length,0);
});
test('a no-store request bypasses even a cached hashed shell asset',()=>{
 const w=worker();assert.equal(w.noStore(),undefined);assert.equal(w.cacheCalls.length,0);
});
test('an absent hashed image fails as an image rather than receiving root HTML',async()=>{
 const w=worker(),response=await w.request('/favicon-abc.svg');assert.equal(response.type,'error');
});
test('offline page navigation may still use the cached app shell',async()=>{
 const w=worker();const response=await w.request('/index.html');assert.equal(await response.text(),'CACHED SHELL');
});
