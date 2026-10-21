'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
function fixture(){
 const source=fs.readFileSync(path.resolve(__dirname,'../../src/web/host.js'),'utf8'),a=source.indexOf('async function upload('),b=source.indexOf('document.addEventListener("change",',a);
 let admission,complete,observed;const requests=[],finished=[],sent=new Promise(r=>observed=r);
 const controller={perform:()=>new Promise(r=>admission=r),adoptLocalSession:s=>finished.push(s),update(){}};
 const ctx={crypto:globalThis.crypto,Uint8Array,Array,JSON,URLSearchParams,viewMode:'view-v1',remoteReady:true,thin:controller,ui:{sel:'A'},currentSession:()=>({sel:'A'}),
  App:{sel:u=>u.sel,uploading:()=> 'file.txt',act:(u,action,value)=>({ui:{...u,completed:JSON.parse(value).thread},cmds:null}),presentation:u=>u},Wire:{plain:x=>x},run(){},later(){},dispatch(){throw Error('unexpected legacy action');},
  fetch:(url,options)=>{requests.push({url,options});observed();return new Promise(r=>complete=()=>r({text:async()=>JSON.stringify({thread:'A',path:'own-file'})}));}};
 vm.createContext(ctx);vm.runInContext(source.slice(a,b),ctx);
 return{ctx,controller,requests,finished,sent,start:()=>ctx.upload('attach',{name:'file.txt',type:'text/plain',size:3}),admit:()=>admission(true),refuse:()=>admission(false),complete:()=>complete()};
}
test('actual upload adapter sends no file body before matching live admission',{timeout:1000},async()=>{
 const f=fixture(),p=f.start();assert.equal(f.requests.length,0);f.admit();await f.sent;assert.equal(f.requests.length,1);assert.equal(new URL(f.requests[0].url,'https://fixture').searchParams.get('thread'),'A');f.complete();await p;assert.equal(f.finished[0].completed,'A');
});
test('refused or overtaken admission does not upload a file',async()=>{
 const f=fixture(),p=f.start();f.refuse();await p;assert.equal(f.requests.length,0);assert.equal(f.finished.length,0);
});
test('old controller HTTP completion cannot write into a replacement controller',{timeout:1000},async()=>{
 const f=fixture(),p=f.start();f.admit();await f.sent;f.ctx.thin={adoptLocalSession:()=>{throw Error('cross controller');}};f.complete();await p;assert.equal(f.finished.length,0);
});
