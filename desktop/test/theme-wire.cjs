'use strict';
// For the theme fixtures, on their synthetic profile only: the page's view.*
// requests and the hub's replies as a bounded chronology (method, action,
// the value of a few navigation actions, ok, the kinds of target and
// nextTarget, remoteReady), and a wait on a fresh action's own reply and,
// when it navigates, the view.open that connects its target. No draft, field
// text, session or other payload is kept.
const fs=require('node:fs'),path=require('node:path');
const VALUES=new Set(['flag','setting','settings-page']);
async function watchViews(page,{limit=600}={}){
 const {cbor,plain}=await import('../../src/web/wire.js');
 const source=fs.readFileSync(path.join(__dirname,'../../src/core/cbor.bend'),'utf8');
 const dict=n=>JSON.parse(new RegExp('def Cbor\\.'+n+'\\(\\) -> List<&2, String>:\\s*(\\[[\\s\\S]*?\\])\\n').exec(source)[1]);
 const keys=dict('keys'),words=dict('words'),cdp=await page.context().newCDPSession(page);
 const log=[],calls=new Map(),waiters=new Set();let seq=0,over=0;
 const short=v=>typeof v==='string'?v.slice(0,64):undefined;
 const note=e=>{e.n=++seq;if(log.length<limit)log.push(e);else over++;for(const w of [...waiters])w();};
 for(const [name,dir] of [['Network.webSocketFrameSent','sent'],['Network.webSocketFrameReceived','received']])cdp.on(name,e=>{
  const at=Date.now();
  try{
   const f=e.response;if(![1,2].includes(f.opcode))return;
   const o=f.opcode===2?plain(cbor(Buffer.from(f.payloadData,'base64'),keys,words)):JSON.parse(f.payloadData);
   if(dir==='sent'&&typeof o?.m==='string'&&o.m.startsWith('view.')){
    const c={method:o.m,action:short(o.p?.action),value:VALUES.has(o.p?.action)?short(o.p?.value):undefined,target:short(o.p?.target?.kind)};
    calls.set(o.id,c);note({at,dir,id:o.id,...c});
   }else if(dir==='received'&&o?.t==='reply'&&calls.has(o.id)){
    const c=calls.get(o.id),r=o.result||{};
    note({at,dir,id:o.id,method:c.method,action:c.action,value:c.value,ok:o.ok!==false&&!o.error,error:short(o.error?.message||o.error),
     target:short(r.target?.kind),nextTarget:short(r.nextTarget?.kind),remoteReady:r.remoteReady===true});
   }else if(dir==='received'&&o?.t==='view.changed')note({at,dir,method:'view.changed'});
  }catch{note({at,dir,decodeFailed:true});}
 });
 await cdp.send('Network.enable');
 const until=(pred,ms,what)=>new Promise((resolve,reject)=>{
  let timer;const check=()=>{const hit=log.find(pred);if(hit){waiters.delete(check);clearTimeout(timer);resolve(hit);}};
  timer=setTimeout(()=>{waiters.delete(check);reject(Object.assign(new Error(`no ${what} within ${ms} ms`),{wire:what}));},ms);
  waiters.add(check);check();});
 return{log,over:()=>over,mark:()=>seq,
  // the first matching action sent after `mark`, its reply, and the view that
  // connects its target (the reply itself, or the view.open its nextTarget starts)
  async acted(mark,action,value,ms=10000){
   const sent=await until(e=>e.n>mark&&e.dir==='sent'&&e.method==='view.action'&&e.action===action&&(value===undefined||e.value===value),ms,`view.action ${action} ${value??''} sent`);
   const reply=await until(e=>e.dir==='received'&&e.id===sent.id,ms,`reply to view.action ${action}`);
   if(!reply.ok)throw Object.assign(new Error(`view.action ${action} refused: ${reply.error}`),{wire:'refused'});
   if(!reply.nextTarget)return{sent,reply,connected:reply};
   const open=await until(e=>e.n>reply.n&&e.dir==='sent'&&e.method==='view.open',ms,`view.open after ${action}`);
   const connected=await until(e=>e.dir==='received'&&e.id===open.id,ms,`reply to view.open after ${action}`);
   if(!connected.ok||!connected.remoteReady)throw Object.assign(new Error(`view.open after ${action} not ready`),{wire:'not ready'});
   return{sent,reply,open,connected};
  }};
}
// what the page says about itself at a step (no content)
const pageState=page=>page.evaluate(()=>({at:Date.now(),ready:document.documentElement.dataset.backplaneRemoteReady||'',cached:document.documentElement.dataset.backplaneCached||'',
 settings:!!document.querySelector('.settings-view'),thread:document.querySelector('main[data-thread]')?.dataset.thread||'',
 light:!!document.querySelector('.app.light'),status:(document.getElementById('view-connection')?.textContent||'').slice(0,160)})).catch(e=>({error:String(e).slice(0,160)}));
// One theme change through Settings, with ONE Close: the chip's own reply and
// its connected view first, then Close's own reply and view, then the
// selected conversation back. A Close the page never sends (the client
// dropped it) or a target that never connects fails here, recorded as such
// in `trail`; it is never retried.
async function chooseTheme(page,views,trail,theme,{narrow=false}={}){
 const entry={theme,narrow,states:[]};trail.push(entry);const state=async step=>entry.states.push({step,...await pageState(page)});
 try{
  if(narrow&&await page.locator('.thread-head .back').first().isVisible())await page.locator('.thread-head .back').first().click();
  await page.locator('.sidebar [data-on-click="flag"][data-value="settings"]').click();
  // Settings keeps its category: the overview's Appearance link is there only on a first open
  await page.waitForFunction(()=>document.querySelector('[data-on-click="settings-page"][data-value="appearance"]')||document.querySelector('[data-on-click="setting"][data-value^="ui.theme="]'));
  const appearance=page.locator('[data-on-click="settings-page"][data-value="appearance"]').first();if(await appearance.count())await appearance.click();
  const chip=page.locator(`[data-on-click="setting"][data-value="ui.theme=${theme}"]`).first();await chip.waitFor({state:'visible'});
  await state('chip');
  let m=views.mark();await chip.click();entry.phase='setting';
  const set=await views.acted(m,'setting',`ui.theme=${theme}`);entry.setting={sent:set.sent.n,reply:set.reply.n,nextTarget:set.reply.nextTarget||'',connected:set.connected.n};
  await page.waitForFunction(theme=>document.querySelector('.app')?.classList.contains('light')===(theme==='light')&&document.documentElement.dataset.backplaneRemoteReady==='true'
   &&document.documentElement.dataset.backplaneCached!=='true'&&!!document.querySelector('.settings-view'),theme);
  await state('set');
  m=views.mark();await page.locator('.settings-view [data-on-click="flag"][data-value="settings"]').click();entry.phase='close';await state('close-clicked');
  const close=await views.acted(m,'flag','settings');entry.close={sent:close.sent.n,reply:close.reply.n,nextTarget:close.reply.nextTarget||'',connected:close.connected.n};
  entry.phase='closed';
  await page.waitForFunction(()=>!document.querySelector('.settings-view')&&!!document.querySelector('main[data-thread]')
   &&document.documentElement.dataset.backplaneRemoteReady==='true'&&document.documentElement.dataset.backplaneCached!=='true');
  await state('back');entry.phase='done';
 }catch(e){
  entry.error=String(e.message||e).slice(0,300);entry.wire=e.wire||'';await state('failed');
  // a Close that never reached the wire after the setting's view was ready is the client dropping a person's click
  if(entry.phase==='close'&&/view\.action flag settings sent/.test(entry.error))entry.finding='Close dropped by the client after the theme setting settled';
  e.trail=true;throw e;
 }
}
module.exports={watchViews,chooseTheme,pageState};
