// Attach to the existing user's Electron UI. No launch, reload, socket close,
// message send, profile copy, or private page/transport payload is retained.
const fs=require('node:fs'),path=require('node:path');
const {pathToFileURL}=require('node:url');
const root=path.resolve(__dirname,'../..'),home=process.env.BACKPLANE_HOME || '/home/h/.backplane-bend';
const out=process.env.UBERBOT_LIVE_OUT;
if(!out)throw Error('UBERBOT_LIVE_OUT is required');
const bot='b1790292962-8017';
const tabs=['chat','mail','space','browser','memory','routines','settings'];
const report={state:'incomplete',client:'existing Electron window, actual profile',bot,tabs:[],wire:[]};
let socket,serial=0;const pending=new Map();
function call(method,params={}){return new Promise((resolve,reject)=>{
 const id=++serial,timer=setTimeout(()=>{pending.delete(id);reject(Error('CDP operation timed out: '+method));},20000);
 pending.set(id,{resolve:r=>{clearTimeout(timer);resolve(r);},reject:e=>{clearTimeout(timer);reject(e);}});
 socket.send(JSON.stringify({id,method,params}));
});}
async function evaluate(fn,arg){const r=await call('Runtime.evaluate',{expression:`(${fn})(${JSON.stringify(arg)})`,awaitPromise:true,returnByValue:true});
 if(r.exceptionDetails)throw Error('UI evaluation failed');return r.result?.value;}
function cats(){return [...document.querySelectorAll('img.cat')].slice(0,24).map(el=>{
 const s=getComputedStyle(el),r=el.getBoundingClientRect();
 return {where:el.closest('.bot-head')?'header':el.closest('aside')?'sidebar':'other',
 name:/^\d+:[a-z]+:\d+$/.test(el.dataset.cat||'')?el.dataset.cat:'invalid',
 display:s.display,visibility:s.visibility,opacity:s.opacity,position:s.position,
 width:r.width,height:r.height,complete:el.complete,naturalWidth:el.naturalWidth,
 sourcePresent:!!el.currentSrc,toolbarCollision:el.matches('.work:empty')};
});}
(async()=>{try{
 fs.mkdirSync(out,{recursive:true,mode:0o700});
 const port=Number(process.env.BACKPLANE_UI_CDP_PORT || fs.readFileSync(path.join(home,'electron-profile/DevToolsActivePort'),'utf8').split('\n')[0]);
 if(!Number.isInteger(port)||port<1||port>65535)throw Error('No active diagnostic port');
 const targets=await(await fetch(`http://127.0.0.1:${port}/json/list`,{signal:AbortSignal.timeout(2000)})).json();
 const target=targets.find(t=>{try{const u=new URL(t.url);return t.type==='page'&&u.hostname==='127.0.0.1'&&u.pathname==='/';}catch{return false;}});
 if(!target)throw Error('Existing Backplane UI target not found');
 const {hello}=require('../service.cjs');
 const advertised=hello(Buffer.from(await(await fetch(new URL('/hello',target.url),{signal:AbortSignal.timeout(2000)})).arrayBuffer()));
 report.source={commit:advertised.commit,version:advertised.backplane};
 socket=new WebSocket(target.webSocketDebuggerUrl);
 await new Promise((resolve,reject)=>{socket.addEventListener('open',resolve,{once:true});socket.addEventListener('error',()=>reject(Error('Could not attach to existing UI')),{once:true});});
 const Wire=await import(pathToFileURL(path.join(root,'src/web/wire.js')));
 const dictionaries=fs.readFileSync(path.join(root,'src/core/cbor.bend'),'utf8');
 const dict=name=>JSON.parse(dictionaries.match(new RegExp('def Cbor\\.'+name+'\\(\\)[^\\n]*\\n\\s*(\\[[\\s\\S]*?\\])'))[1]);
 const keys=dict('keys'),words=dict('words'),allowed=new Set(tabs);
 socket.addEventListener('message',event=>{let m;try{m=JSON.parse(event.data);}catch{return;}
  if(m.id){const p=pending.get(m.id);pending.delete(m.id);if(p)m.error?p.reject(Error('CDP command refused')):p.resolve(m.result);return;}
  if(!['Network.webSocketFrameSent','Network.webSocketFrameReceived','Network.webSocketClosed'].includes(m.method)||report.wire.length>=256)return;
  const p=m.params,entry={direction:m.method.endsWith('Sent')?'sent':m.method.endsWith('Received')?'received':'closed',at:p.timestamp*1000};
  if(p.response){const bytes=Buffer.from(p.response.payloadData,p.response.opcode===2?'base64':'utf8');entry.bytes=bytes.length;
   // Decode only to correlate IDs and allowlisted tab names; discard the tree.
   const v=Wire.plain(Wire.cbor(bytes,keys,words));
   if(['view.action','view.update','view.open'].includes(v?.m)){entry.method=v.m;entry.id=v.id;
    if(v.p?.action==='bot-tab'&&allowed.has(v.p?.value))entry.tab=v.p.value;}
   else if(v?.t==='reply'){entry.id=v.id;entry.ok=v.ok===true;entry.ready=v.result?.remoteReady===true;
    if(allowed.has(v.result?.session?.route?.tab))entry.tab=v.result.session.route.tab;}
   else if(['hb','view.changed'].includes(v?.t))entry.type=v.t;
  }report.wire.push(entry);
 });
 await call('Network.enable');
 report.before=await evaluate(cats);
 report.context=await evaluate(()=>({thread:document.querySelector('main')?.dataset.thread||'',
  selectedTabs:[...document.querySelectorAll('.bot-tabs .tab.on')].map(x=>x.dataset.value),
  remoteReady:document.documentElement.dataset.backplaneRemoteReady,visibility:document.visibilityState}));
 await evaluate(()=>{window.__bpUberProbe={longTasks:[]};try{const o=new PerformanceObserver(list=>{for(const e of list.getEntries())if(window.__bpUberProbe.longTasks.length<128)window.__bpUberProbe.longTasks.push({at:e.startTime,ms:e.duration});});o.observe({type:'longtask',buffered:false});window.__bpUberProbe.observer=o;}catch{}});
 await evaluate(bot=>{const el=document.querySelector(`.uber-row[data-value="${bot}"]`);if(!el)throw Error('Expected Bub uberbot row is absent');el.click();},bot);
 // Wait by DOM events, not by repeatedly polling the service.
 await evaluate(()=>new Promise(resolve=>{let observer;const done=()=>{clearTimeout(timer);observer?.disconnect();resolve(!!document.querySelector('.bot-head'));};
  const timer=setTimeout(done,10000);observer=new MutationObserver(()=>{if(document.querySelector('.bot-head'))done();});observer.observe(document.documentElement,{subtree:true,childList:true});if(document.querySelector('.bot-head'))done();}));
 for(const tab of tabs){
  const result=await evaluate(tab=>new Promise(resolve=>{
   const button=[...document.querySelectorAll('.bot-tabs [data-on-click="bot-tab"]')].find(x=>x.dataset.value===tab);
   if(!button){resolve({tab,supported:false});return;}
   const at=performance.now();let feedback=null,observer,finished=false;
   const done=timedOut=>{if(finished)return;finished=true;clearTimeout(timer);observer.disconnect();requestAnimationFrame(()=>requestAnimationFrame(()=>resolve({tab,supported:true,timedOut,clickAt:at,feedbackMs:feedback===null?null:feedback-at,contentReadyMs:timedOut?null:performance.now()-at,
    selectedTabs:[...document.querySelectorAll('.bot-tabs .tab.on')].map(x=>x.dataset.value)})));};
   const check=()=>{const current=[...document.querySelectorAll('.bot-tabs .tab.on')].some(x=>x.dataset.value===tab);
    if(current&&feedback===null)feedback=performance.now();if(current&&document.documentElement.dataset.backplaneRemoteReady==='true')done(false);};
   const timer=setTimeout(()=>done(true),10000);observer=new MutationObserver(check);observer.observe(document.documentElement,{subtree:true,childList:true,attributes:true});button.click();check();
  }),tab);
  result.cats=await evaluate(cats);report.tabs.push(result);
 }
 report.after=await evaluate(cats);
 report.longTasks=await evaluate(()=>{const p=window.__bpUberProbe;p?.observer?.disconnect();delete window.__bpUberProbe;return p?.longTasks||[];});
 report.state='observed';
 // Restore the person's starting selection using only ordinary UI navigation.
 report.restored=await evaluate(context=>{const values=context.selectedTabs;let button;
  if(values?.length)button=[...document.querySelectorAll('[data-on-click="bot-tab"]')].find(x=>x.dataset.value===values.at(-1));
  else if(context.thread)button=[...document.querySelectorAll('[data-on-click="select"]')].find(x=>x.dataset.value===context.thread);
  if(button){button.click();return true;}return false;},report.context);
}catch(error){report.failure=String(error.message);process.exitCode=1;}
finally{if(socket){try{await evaluate(()=>{window.__bpUberProbe?.observer?.disconnect();delete window.__bpUberProbe;});}catch{}socket.close();}
 fs.mkdirSync(out,{recursive:true,mode:0o700});fs.writeFileSync(path.join(out,'RESULT.json'),JSON.stringify(report,null,2),{mode:0o600});
 console.log(JSON.stringify({state:report.state,rc:process.exitCode||0,tabs:report.tabs.map(x=>({tab:x.tab,supported:x.supported,feedbackMs:x.feedbackMs,contentReadyMs:x.contentReadyMs,timedOut:x.timedOut})),result:path.join(out,'RESULT.json')}));}
})();
