'use strict';
// Requires the backend owner's captured, real Lr fixture. No Bend compilation,
// browser/server launch, network, transcript read or guessed source-thread RPC.
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),crypto=require('node:crypto');
const list=xs=>xs.reduceRight((tail,head)=>({$:'Con',head,tail}),{$:'Nil'});
const kids=n=>{const out=[];for(let xs=n?.kids;xs?.head;xs=xs.tail)out.push(xs.head);return out;};
const all=n=>[n,...kids(n).flatMap(all)];
const attr=(n,name)=>{for(let xs=n?.attrs;xs?.head;xs=xs.tail)if(xs.head.name===name)return xs.head.value;};
const action=n=>{for(let xs=n?.attrs;xs?.head;xs=xs.tail)if(xs.head.event==='click')return xs.head.action;};
const el=(tag,attrs={},children=[])=>({$:'El',tag,key:'',attrs:list(Object.entries(attrs).map(([name,value])=>({$:'At',name,value}))),kids:list(children)});
const text=text=>({$:'Txt',text});
function realFixture(){
 const file=process.env.LR_WHOLE_FIXTURE_LOG,sha=process.env.LR_WHOLE_FIXTURE_SHA256;
 assert(file&&/^[a-f0-9]{64}$/.test(sha||''),'Set LR_WHOLE_FIXTURE_LOG and its exact captured SHA256 from backend lr_whole_test');
 const bytes=fs.readFileSync(file);assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'),sha);
 const lines=bytes.toString('utf8').split('\n').filter(s=>s.startsWith('fixture '));assert.equal(lines.length,1,'One original backend fixture line required');
 const f=JSON.parse(lines[0].slice(8));assert.equal(f.entryId,'t:'+f.source+':lr-r9');assert.equal(f.owner,'t0');assert(/^(0|[1-9][0-9]*)$/.test(f.version));
 assert(f.preview.endsWith('…\n\n(cut short: thread_read '+f.source+' for the rest)'));assert([...f.fullText].length>1500&&Buffer.byteLength(f.fullText)<=8192);assert.notEqual(f.preview,f.fullText);assert.equal(f.newReport,f.fullText);
 return f;
}
test('real Lr legacy report: actual click dispatch and ThinHost reply show the complete canonical text inline',async()=>{
 const f=realFixture(),{ThinHost}=await import('../../src/web/thin-host.js'),{ThinViews,VIEW_LIMITS}=await import('../../src/web/thin.js'),{ThinContinuations}=await import('../../src/web/thin-continuations.js');
 const hostSource=fs.readFileSync(path.join(__dirname,'../../src/web/host.js'),'utf8'),reader=new ThinContinuations(),sent=[],warnings=[],commands=[];
 let session={sel:f.owner,rid:1,drafts:{[f.owner]:'Retain 日本語 👩‍💻'},open:{},info:{},outbox:{}},rendered,paints=0;
 const first=el('button',{'data-value':JSON.stringify({entryId:f.entryId,cursor:''})},[text('More')]);first.attrs=list([...function*(){for(let xs=first.attrs;xs?.head;xs=xs.tail)yield xs.head;}(),{$:'On',event:'click',action:'thin-message-more'}]);
 const original=el('div',{id:'timeline'},[el('div',{class:'msg user','data-id':f.entryId},[el('div',{class:'body plain'},[text(f.preview)])]),first]);
 const context={viewMode:'view-v1',thinContinuations:reader,showViewStatus:s=>warnings.push(s),later(){paints++;rendered=reader.project(original,n=>n);}};
 vm.createContext(context);
 const showStart=hostSource.indexOf('function showThinMessage(message)'),showEnd=hostSource.indexOf('function stopThin()',showStart);
 const show=vm.runInContext('('+hostSource.slice(showStart,showEnd)+')',context);
 const api={hub:'https://fixture',cid:'real-lr-reader',now:()=>0,session:()=>session,target:()=>({kind:'thread',id:f.owner}),counter(){},send:r=>sent.push(r),choice:s=>s,prepare:s=>s,local(){},sessionChanged:s=>session=s,ack:s=>s,decode:()=>original,command:c=>commands.push(c),state(){},anchor:()=>({id:f.entryId,offset:0}),blocked(){},warning:s=>warnings.push(s),message:show,
  view:(node,detail)=>{reader.bind('https://fixture',detail);rendered=reader.project(node,n=>n);}};
 const host=new ThinHost(api,ThinViews,2**47);context.thin=host;
 const reply=(request,result)=>({t:'reply',id:request.id,ok:true,result:{version:1,hub:api.hub,generation:'7',epoch:'epoch',requestRevision:request.p.requestRevision,target:request.p.target,viewId:request.p.viewId||'parent-view',viewRevision:'1',renderer:'web',cmds:[],...result}});
 host.greeting({t:'view',version:1,renderer:'web',generation:'7',epoch:'epoch',limits:{...VIEW_LIMITS}});
 host.receive(reply(sent.at(-1),{remoteReady:true,shown:{type:'text',text:f.preview},session,window:{ids:[f.version],older:'',hasMore:false,anchor:{id:f.entryId,offset:0},partial:[{id:f.entryId,version:f.version,cursor:JSON.stringify({version:1,epoch:'epoch',target:{kind:'thread',id:f.owner},query:'message:'+f.version,before:'1'}),reason:'byte-limit',hasMore:true,complete:false}]}}));
 const button=all(rendered).find(n=>action(n)==='thin-message-more');assert(button);assert.equal(kids(button)[0].text,'Read rest of message');assert.equal(sent.length,1,'No automatic body reads');
 const dispatchStart=hostSource.indexOf('function dispatch('),dispatchEnd=hostSource.indexOf('Plot2d.onPlace',dispatchStart);vm.runInContext(hostSource.slice(dispatchStart,dispatchEnd),context);
 assert(context.dispatch(action(button),attr(button,'data-value')));assert.equal(sent.length,2);const request=sent.at(-1);
 assert.equal(request.m,'view.message');assert.equal(request.p.entryId,f.entryId);assert.equal(request.p.target.id,f.owner);assert.equal(request.p.cursor,'');
 host.receive(reply(request,{remoteReady:false,message:{id:f.entryId,thread:f.owner,version:f.version,text:f.fullText,cursor:'',hasMore:false,complete:true}}));
 const row=all(rendered).find(n=>attr(n,'data-id')===f.entryId),pre=all(row).find(n=>n.tag==='pre');assert(pre);assert.equal(kids(pre)[0].text,f.fullText);assert.equal(kids(pre)[0].tag,undefined,'Whole report remains plaintext');
 assert(!all(row).some(n=>n.tag==='button'));assert(!all(row).some(n=>attr(n,'class')==='body plain'),'Shortened preview is replaced');assert.equal(reader.readers.get(f.entryId).complete,true);assert.equal(session.sel,f.owner);assert.equal(session.drafts[f.owner],'Retain 日本語 👩‍💻');assert.equal(commands.length,0);assert.equal(paints,1);assert.deepEqual(warnings,['']);assert.equal(sent.length,2);
});
