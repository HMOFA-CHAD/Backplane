'use strict';
// Combined-batch acceptance helper. The integrator supplies the SAME running
// Electron fixture used for the other UI checks. This launches no browser/app,
// builds nothing, and never touches a person's home, cookies or accounts.
const assert=require('node:assert/strict');
const http=require('node:http');
const fs=require('node:fs');
const path=require('node:path');
const {randomUUID}=require('node:crypto');

async function controlledBrowserPage(){
 const session=randomUUID();
 const server=http.createServer((req,res)=>{
  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.setHeader('X-Frame-Options','DENY');
  res.setHeader('Content-Security-Policy',"default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; frame-ancestors 'none'; connect-src 'none'; form-action 'none'");
  if(!/fixtureSession=/.test(req.headers.cookie||''))res.setHeader('Set-Cookie',`fixtureSession=${session}; HttpOnly; SameSite=Strict; Path=/; Max-Age=3600`);
  const second=req.url.startsWith('/two');
  res.end(`<!doctype html><meta charset="utf-8"><title>Shared Browser ${second?'two':'one'}</title>
<style>body{background:#16313a;color:white;font:18px system-ui;padding:20px}input,button,a{font:inherit;margin:8px;padding:8px}a{color:#ffe084}#scroller{height:100px;overflow:auto;border:2px solid white}#long{height:1000px}output{display:block}</style>
<h1>Shared Browser ${second?'two':'one'}</h1>
<label>Shared entry<input id="entry" aria-label="Shared entry"></label>
<button id="count">Count locally</button><output id="counted">Count: 0</output><output id="echo">Entry: </output>
<form id="form"><label>Form entry<input id="formEntry" aria-label="Form entry"></label><button>Save locally</button></form><output id="submitted">Saves: 0</output>
<a id="next" href="/${second?'one':'two'}">Go to ${second?'one':'two'}</a>
<div id="scroller"><div id="long">Scroll the same page</div><span>End of scroll region</span></div>
<script>
window.fixtureState={document:crypto.randomUUID(),count:0,saves:0,trustedClicks:0,trustedInputs:0};
sessionStorage.fixtureTab||=(crypto.randomUUID());localStorage.fixtureProfile||=(crypto.randomUUID());
document.querySelector('#count').addEventListener('click',e=>{fixtureState.count++;fixtureState.trustedClicks+=Number(e.isTrusted);document.querySelector('#counted').textContent='Count: '+fixtureState.count});
document.querySelector('#entry').addEventListener('input',e=>{fixtureState.trustedInputs+=Number(e.isTrusted);document.querySelector('#echo').textContent='Entry: '+e.target.value});
document.querySelector('#form').addEventListener('submit',e=>{e.preventDefault();fixtureState.saves++;document.querySelector('#submitted').textContent='Saves: '+fixtureState.saves});
</script>`);
 });
 await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
 return{origin:`http://127.0.0.1:${server.address().port}`,close:()=>new Promise(resolve=>server.close(resolve))};
}

async function runSharedBrowserAcceptance({app,page,origin,token,threadId,otherThreadId,out}){
 assert(app&&page&&origin&&token&&threadId&&out,'use the integrator\'s isolated running Electron fixture');
 fs.mkdirSync(out,{recursive:true});
 const fromTakeover=process.env.BROWSER_CONTINUE_TAKEOVER==='1';
 const retainedPrefix=fromTakeover?JSON.parse(fs.readFileSync(process.env.BROWSER_PREFIX_RECEIPT,'utf8')):null;
 const prefixChecks=['native snapshot carries actual page and PNG','visible sandboxed WebContentsView, no iframe','bot ref input reaches the visible native document','bot scroll uses actual native page'];
 if(retainedPrefix)assert(prefixChecks.every(name=>retainedPrefix.checks.includes(name)),'continuation requires actual retained native prefix');
 const retained=retainedPrefix?{receipt:process.env.BROWSER_PREFIX_RECEIPT,checks:prefixChecks}:null;
 const site=await controlledBrowserPage(),checks=[];
 let guestId=null,phase='setup';
 const ownership={native:[],renderer:[]},wire={frames:[],decodeErrors:0};
 let wireTap;
 let requestId=1000;
 const check=(name,condition)=>{assert(condition,name);checks.push(name);};
 async function tool(name,args={},owner=threadId,allowError=false){
  const response=await fetch(`${origin}/mcp/${encodeURIComponent(owner)}`,{method:'POST',redirect:'error',signal:AbortSignal.timeout(20000),
   headers:{authorization:`Bearer ${token}`,'content-type':'application/json',accept:'application/json'},
   body:JSON.stringify({jsonrpc:'2.0',id:++requestId,method:'tools/call',params:{name,arguments:args}})});
  assert(response.ok,`${name}: HTTP ${response.status}`);
  const reply=await response.json();assert(!reply.error,`${name}: RPC refused`);
  const result=reply.result;
  if(allowError)return result;
  assert.equal(result?.isError,false,`${name}: ${result?.content?.find(x=>x.type==='text')?.text}`);
  const text=result.content.find(x=>x.type==='text')?.text;
  return{value:text?JSON.parse(text):null,images:result.content.filter(x=>x.type==='image')};
 }
 async function select(owner){
  await page.locator(`[data-on-click="select"][data-value="${owner}"]`).first().click();
  await page.waitForFunction(id=>document.querySelector('main')?.dataset.thread===id&&document.documentElement.dataset.backplaneRemoteReady==='true',owner);
  await page.locator('[data-on-click="view-kind"][data-value="browser"]').first().click();
  await page.locator(`[data-desktop-browser-owner="${owner}"]`).waitFor();
 }
 const native=async()=>app.evaluate(({BrowserWindow},siteOrigin)=>{
  const w=BrowserWindow.getAllWindows().find(w=>!w.isDestroyed());
  return w.contentView.children.filter(v=>v.webContents&&!v.webContents.isDestroyed()).map(v=>({id:v.webContents.id,url:v.webContents.getURL(),visible:v.getVisible(),bounds:v.getBounds(),
   preferences:{sandbox:v.webContents.getLastWebPreferences().sandbox,nodeIntegration:v.webContents.getLastWebPreferences().nodeIntegration,contextIsolation:v.webContents.getLastWebPreferences().contextIsolation}})).filter(v=>v.url.startsWith(siteOrigin));
 },site.origin);
 const inspect=async id=>app.evaluate(({webContents},id)=>webContents.fromId(id).executeJavaScript(`JSON.stringify({...fixtureState,entry:document.querySelector('#entry').value,active:document.activeElement?.id,hasFocus:document.hasFocus(),profile:localStorage.fixtureProfile,tab:sessionStorage.fixtureTab})`).then(JSON.parse),id);
 const humanClick=async(id,selector)=>app.evaluate(async({webContents},{id,selector})=>{
  const wc=webContents.fromId(id),point=await wc.executeJavaScript(`(()=>{const r=document.querySelector(${JSON.stringify(selector)}).getBoundingClientRect();return {x:Math.round(r.x+r.width/2),y:Math.round(r.y+r.height/2)}})()`);
  wc.sendInputEvent({type:'mouseDown',button:'left',clickCount:1,...point});wc.sendInputEvent({type:'mouseUp',button:'left',clickCount:1,...point});
 },{id,selector});
 const refFor=(snapshot,role,name)=>{
  const line=snapshot.outline.split('\n').find(line=>line.includes('- '+role+' '+JSON.stringify(name)));
  const ref=/\[ref=(e\d+)\]/.exec(line||'')?.[1];assert(ref,`snapshot ref for ${role} ${name}`);return ref;
 };
 try{
  const {cbor,plain}=await import('../../src/web/wire.js');
  const codec=fs.readFileSync(path.join(__dirname,'../../src/core/cbor.bend'),'utf8');
  const dictionary=name=>JSON.parse(new RegExp('def Cbor\\.'+name+'\\(\\) -> List<&2, String>:\\s*(\\[[\\s\\S]*?\\])\\n').exec(codec)[1]);
  const keys=dictionary('keys'),words=dictionary('words');wireTap=await page.context().newCDPSession(page);
  const record=(direction,e)=>{try{
   const f=e.response,o=f.opcode===2?plain(cbor(Buffer.from(f.payloadData,'base64'),keys,words)):f.opcode===1?JSON.parse(f.payloadData):null;
   if(!o||typeof o!=='object'){wire.decodeErrors++;return;}
   if(!['view.open','view.action','view.update','bots.browser'].includes(o.m)&&!['reply','view.changed'].includes(o.t))return;
   const p=o.p||{},r=o.result||{};let takeover=false,handback=false;
   const visit=n=>{if(!n||typeof n!=='object')return;for(const a of n.attrs||[])if(a.name==='data-on-click'){takeover||=a.value==='tk-takeover';handback||=a.value==='tk-handback';}for(const k of n.kids||[])visit(k);};visit(r.shown);
   const methods=(r.cmds||[]).filter(c=>c.type==='send').map(c=>{try{const rpc=JSON.parse(c.text);return{method:rpc.m,...(rpc.m==='bots.browser'?{ownerMatches:rpc.p?.bot===threadId,op:rpc.p?.op}:{})};}catch{return{invalid:true};}});
   if(wire.frames.length>=128)wire.frames.shift();
   wire.frames.push({direction,id:o.id,type:o.t,method:o.m,action:p.action,ownerMatches:o.m==='bots.browser'?p.bot===threadId:['tk-takeover','tk-handback'].includes(p.action)?p.value===threadId:undefined,op:o.m==='bots.browser'?p.op:undefined,ok:o.ok,errorCode:typeof o.error==='object'?o.error?.code:undefined,requestRevision:p.requestRevision??r.requestRevision,viewRevision:o.viewRevision??r.viewRevision,takeover,handback,methods});
  }catch{wire.decodeErrors++;}};
  wireTap.on('Network.webSocketFrameSent',e=>record('sent',e));wireTap.on('Network.webSocketFrameReceived',e=>record('received',e));await wireTap.send('Network.enable');
  await page.waitForFunction(async()=>window.backplaneDesktop?.browser&&(await window.backplaneDesktop.browser.state()).phase==='ready');
  await select(threadId);
  await tool('preview_open',{url:site.origin+'/one'});
  await page.locator(`[data-bfield="brurl:${threadId}"]`).waitFor();
  let snapshot=(await tool('preview_snapshot',{screenshot:true}));
  if(!fromTakeover)check('native snapshot carries actual page and PNG',snapshot.value.title==='Shared Browser one'&&snapshot.images.length===1);
  const views=await native();assert.equal(views.length,1);const id=views[0].id;guestId=id;
  if(!fromTakeover)check('visible sandboxed WebContentsView, no iframe',views[0].visible&&views[0].bounds.width>100&&views[0].bounds.height>80&&views[0].preferences.sandbox&&views[0].preferences.contextIsolation&&!views[0].preferences.nodeIntegration&&await page.locator('iframe').count()===0);
  const initial=await inspect(id);
  if(!fromTakeover){
  const refInput={initial};
  await app.evaluate(({webContents},id)=>{
   const wc=webContents.fromId(id),probe={events:[]};wc.__sharedBrowserProbe=probe;
   const record=(name,event,input)=>{if(probe.events.length<50)probe.events.push({event:name,type:input?.type||'',prevented:event?.defaultPrevented===true,focusedId:webContents.getFocusedWebContents()?.id??null});};
   for(const name of ['before-input-event','before-mouse-event','focus','blur'])wc.on(name,(event,input)=>record(name,event,input));
  },id);
  await tool('preview_type',{ref:refFor(snapshot.value,'textbox','Shared entry'),text:'bot typed',clear:true});
  refInput.afterType=await inspect(id);
  await tool('preview_click',{ref:refFor(snapshot.value,'button','Count locally')});
  refInput.afterClick=await inspect(id);
  refInput.inputEvents=await app.evaluate(({webContents},id)=>webContents.fromId(id).__sharedBrowserProbe.events,id);
  // Observe a later renderer turn without repeating any input.
  await app.evaluate(async({webContents},id)=>webContents.fromId(id).executeJavaScript('new Promise(resolve=>setTimeout(()=>resolve(true),150))'),id);
  refInput.settled=await inspect(id);
  refInput.settledInputEvents=await app.evaluate(({webContents},id)=>webContents.fromId(id).__sharedBrowserProbe.events,id);
  fs.writeFileSync(path.join(out,'ref-input-observation.json'),JSON.stringify({state:refInput.afterClick,observations:refInput,expectedEntry:'bot typed',expectedCount:1},null,2));
  check('bot ref input reaches the visible native document',refInput.afterClick.entry==='bot typed'&&refInput.afterClick.count===1);
  await tool('preview_scroll',{selector:'#scroller',dy:300});
  check('bot scroll uses actual native page',(await tool('preview_evaluate',{expression:'document.querySelector("#scroller").scrollTop'})).value>0);
  await tool('preview_wait_for',{text:'Entry: bot typed'});
  }
  const beforeHuman=await inspect(id);
  phase='takeover';
  await page.evaluate(()=>{
   const probe={events:[]};window.__sharedBrowserTakeover=probe;
   probe.off=window.backplaneDesktop.browser.onTakeover(value=>{if(probe.events.length<20)probe.events.push({owner:value.owner,at:Date.now(),remoteReady:document.documentElement.dataset.backplaneRemoteReady});});
  });
  // Native input goes to the ACTUAL topmost shield in the same window. It
  // consumes the click; only canonical Teach takeover unlocks the guest.
  ownership.nativeBefore=await app.evaluate(async({BrowserWindow,webContents})=>{
   const w=BrowserWindow.getAllWindows().find(w=>!w.isDestroyed()),shield=w.contentView.children.find(v=>v.getVisible()&&v.webContents?.getURL().endsWith('/browser-shield.html'));
   if(!shield)throw Error('Actual Browser shield missing');
   if(w.contentView.children.at(-1)!==shield)throw Error('Actual Browser shield is not topmost');
   const probe={events:[],beforeWindowFocused:w.isFocused(),focusedId:webContents.getFocusedWebContents()?.id??null};w.__sharedBrowserOwnership=probe;
   shield.webContents.on('before-mouse-event',(event,input)=>{if(probe.events.length<20)probe.events.push({type:input?.type,button:input?.button,prevented:event.defaultPrevented===true,windowFocused:w.isFocused()});});
   // sendInputEvent requires a focused containing BrowserWindow. This is a
   // fixture prerequisite only; no product focus/ownership guard is changed.
   // https://www.electronjs.org/docs/latest/api/web-contents#contentssendinputeventinputevent
   if(!w.isFocused())await new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>{w.removeListener('focus',done);reject(Error('Fixture BrowserWindow did not focus'));},2000);
    function done(){clearTimeout(timer);w.removeListener('focus',done);resolve();}
    w.once('focus',done);w.focus();if(w.isFocused())done();
   });
   probe.dispatchWindowFocused=w.isFocused();
   shield.webContents.sendInputEvent({type:'mouseDown',button:'left',clickCount:1,x:20,y:20});
   shield.webContents.sendInputEvent({type:'mouseUp',button:'left',clickCount:1,x:20,y:20});
   return probe;
  });
  await page.locator(`[data-on-click="tk-handback"][data-value="${threadId}"]`).waitFor();
  fs.writeFileSync(path.join(out,'takeover-observation.json'),JSON.stringify({
   native:await app.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows().find(w=>!w.isDestroyed())?.__sharedBrowserOwnership),
   renderer:await page.evaluate(()=>({events:window.__sharedBrowserTakeover?.events||[],remoteReady:document.documentElement.dataset.backplaneRemoteReady,strip:document.querySelector('.desktop-browser-drive')?.textContent}))
  },null,2)+'\n');
  check('takeover consumes its click',(await inspect(id)).count===beforeHuman.count);
  phase='human';
  check('bot click refused while human owns page',(await tool('preview_click',{selector:'#count'},threadId,true)).isError===true);
  check('bot evaluation refused while human owns page',(await tool('preview_evaluate',{expression:'window.fixtureState.count++'},threadId,true)).isError===true);
  await humanClick(id,'#entry');
  await app.evaluate(({webContents},id)=>{
   const wc=webContents.fromId(id);wc.focus();
   wc.sendInputEvent({type:'keyDown',keyCode:'A',modifiers:[process.platform==='darwin'?'meta':'control']});wc.sendInputEvent({type:'keyUp',keyCode:'A',modifiers:[process.platform==='darwin'?'meta':'control']});
   for(const keyCode of 'human typed')wc.sendInputEvent({type:'char',keyCode});
  },id);
  await humanClick(id,'#count');
  const human=await inspect(id);
  check('trusted native human input changes SAME document',human.document===initial.document&&human.entry==='human typed'&&human.count===beforeHuman.count+1&&human.trustedClicks===beforeHuman.trustedClicks+1&&human.trustedInputs>beforeHuman.trustedInputs);
  phase='handback';
  await page.locator(`[data-on-click="tk-handback"][data-value="${threadId}"]`).click();
  await page.locator(`[data-on-click="tk-takeover"][data-value="${threadId}"]`).waitFor();
  snapshot=await tool('preview_snapshot');
  check('handback snapshot sees actual human edits',snapshot.value.visibleText.includes('Entry: human typed')&&snapshot.value.visibleText.includes('Count: '+(beforeHuman.count+1)));
  phase='remaining-browser';
  await tool('preview_click',{locator:'role=button[name="Count locally"]'});
  await tool('preview_type',{locator:'role=textbox[name="Form entry"]',text:'local only',clear:true});
  await tool('preview_press',{key:'Enter'});
  check('role locator and Enter submit locally',(await inspect(id)).saves===1);
  await tool('preview_navigate',{url:site.origin+'/two',readiness:'domContentLoaded'});
  await tool('preview_wait_for',{url:'/two',text:'Shared Browser two'});
  check('navigation keeps actual guest identity',(await native()).some(v=>v.id===id&&v.url.endsWith('/two')));
  check('old document refs refused',(await tool('preview_click',{ref:refFor(snapshot.value,'button','Count locally')},threadId,true)).isError===true);
  check('refusal does not break fresh snapshots',(await tool('preview_snapshot')).value.title==='Shared Browser two');
  // UI address/history/reload use the same service intent pipeline.
  await page.locator('[data-on-click="br-back"]').first().click();
  await page.waitForFunction(async()=>document.querySelector('.browser-tab.on')?.textContent.includes('one'));
  await page.locator('[data-on-click="br-forward"]').first().click();
  await page.waitForFunction(()=>document.querySelector('.browser-tab.on')?.textContent.includes('two'));
  await page.locator('[data-on-click="br-reload"]').first().click();
  await page.reload();
  await page.waitForFunction(()=>document.documentElement.dataset.backplaneRemoteReady==='true');
  await page.locator(`[data-desktop-browser-owner="${threadId}"]`).waitFor();
  const retained=(await native()).find(v=>v.id===id);
  check('renderer reload re-presents existing guest',retained?.visible===true);
  const after=await inspect(id);
  check('profile and tab storage retained across navigation/reload',initial.profile===after.profile&&initial.tab===after.tab);
  await app.evaluate(async({webContents},id)=>{await webContents.fromId(id).session.cookies.flushStore();},id);
  check('guest session cookie retained',await app.evaluate(async({webContents},{id,url})=>(await webContents.fromId(id).session.cookies.get({url,name:'fixtureSession'})).length===1,{id,url:site.origin}));
  const originalTab=await page.locator('[data-on-click="br-select"]').first().getAttribute('data-value');
  await page.locator('[data-on-click="br-new"]').first().click();
  await page.waitForFunction(()=>document.querySelectorAll('[data-on-click="br-select"]').length===2);
  const newTab=await page.locator('[data-on-click="br-select"]').last().getAttribute('data-value');
  const address=page.locator(`[data-bfield="brurl:${threadId}"]`);
  await address.fill(site.origin+'/one');await page.locator('[data-on-click="br-go"]').first().click();
  await page.waitForFunction(()=>document.querySelector('.browser-tab.on')?.textContent.includes('one'));
  check('new tab is a distinct visible native guest',(await native()).some(v=>v.id!==id&&v.visible&&v.url.endsWith('/one')));
  await page.locator(`[data-on-click="br-select"][data-value="${originalTab}"]`).click();
  check('tab selection restores exact original guest',(await native()).find(v=>v.id===id)?.visible===true);
  await page.locator(`[data-on-click="br-close"][data-value="${newTab}"]`).click();
  await page.waitForFunction(()=>document.querySelectorAll('[data-on-click="br-select"]').length===1);
  await page.locator(`[data-on-click="tk-handback"][data-value="${threadId}"]`).click();
  await page.locator(`[data-on-click="tk-takeover"][data-value="${threadId}"]`).waitFor();
  check('preview follows user-selected tab',(await tool('preview_snapshot')).value.title==='Shared Browser two');
  if(otherThreadId){
   await select(otherThreadId);await tool('preview_open',{url:site.origin+'/two'},otherThreadId);
   await select(threadId);
   check('thread switch restores its actual guest',(await native()).filter(v=>v.visible).every(v=>v.id===id));
  }
  await page.screenshot({path:path.join(out,'shared-browser-chrome.png')});
  const pixels=await app.evaluate(async({webContents},id)=>(await webContents.fromId(id).capturePage()).toPNG().toString('base64'),id);
  fs.writeFileSync(path.join(out,'shared-browser-guest.png'),Buffer.from(pixels,'base64'));
  const receipt={status:'PASS',checks,retainedPrefix:retained,guestId:id,scope:'Actual Electron native guest + authenticated preview MCP + trusted human input; isolated controlled local page only',remaining:['physical manual input/IME','full Electron exit/relaunch cookie and tab restoration','remote machine browser attachment/reconnect','popup adoption (current guest policy denies unqualified popups)']};
  fs.writeFileSync(path.join(out,'shared-browser.json'),JSON.stringify(receipt,null,2)+'\n');
  return receipt;
 }catch(error){
  // Retain this exact failure boundary before another helper changes the UI.
  try{ownership.renderer=await page.evaluate(()=>({events:window.__sharedBrowserTakeover?.events||[],remoteReady:document.documentElement.dataset.backplaneRemoteReady,thread:document.querySelector('main')?.dataset.thread,strip:document.querySelector('.desktop-browser-drive')?.textContent,controls:[...document.querySelectorAll('.desktop-browser-drive [data-on-click]')].map(n=>({action:n.dataset.onClick,value:n.dataset.value})),status:document.querySelector('.desktop-browser-status')?.textContent}));}catch(e){ownership.rendererError=e.message;}
  try{ownership.native=await app.evaluate(({BrowserWindow,webContents},id)=>{const w=BrowserWindow.getAllWindows().find(w=>!w.isDestroyed());return{probe:w?.__sharedBrowserOwnership,windowFocused:w?.isFocused(),focusedId:webContents.getFocusedWebContents()?.id??null,views:w?.contentView.children.filter(v=>v.webContents).map(v=>({id:v.webContents.id,url:v.webContents.getURL(),visible:v.getVisible(),bounds:v.getBounds(),guest:v.webContents.id===id}))};},guestId);}catch(e){ownership.nativeError=e.message;}
  if(phase==='takeover')try{const probe=await tool('preview_snapshot',{},threadId,true);ownership.canonicalSnapshotProbe={isError:probe.isError,text:probe.content?.find(c=>c.type==='text')?.text?.slice(0,400)};}catch(e){ownership.canonicalProbeError=e.message;}
  try{fs.writeFileSync(path.join(out,'browser-failure.html'),await page.content());await page.screenshot({path:path.join(out,'browser-failure.png')});}catch(e){ownership.captureError=e.message;}
  // Preserve the failed native attempt before one alternate visible-control
  // diagnostic. Its outcome cannot turn the original failure into a PASS.
  if(phase==='takeover'){
   ownership.wireAtNativeFailure=wire.frames.length;
   try{
    const ui=page.locator(`[data-on-click="tk-takeover"][data-value="${threadId}"]`);
    await ui.click({timeout:2000});
    await page.locator(`[data-on-click="tk-handback"][data-value="${threadId}"]`).waitFor({timeout:5000});
    ownership.alternateUiTakeover={handback:true};
   }catch(e){ownership.alternateUiTakeover={handback:false,error:e.message};}
  }
  fs.writeFileSync(path.join(out,'ownership-wire.json'),JSON.stringify(wire,null,2)+'\n');
  fs.writeFileSync(path.join(out,'ownership-observation.json'),JSON.stringify({phase,ownership},null,2)+'\n');
  fs.writeFileSync(path.join(out,'shared-browser.json'),JSON.stringify({status:'FAIL',checks,retainedPrefix:retained,phase,error:error.stack,scope:'No deployment acceptance claimed'},null,2)+'\n');throw error;
 }
 finally{if(wireTap)await wireTap.detach().catch(()=>{});await site.close();}
}
module.exports={controlledBrowserPage,runSharedBrowserAcceptance};
