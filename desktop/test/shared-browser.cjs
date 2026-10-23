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
 const fromHuman=process.env.BROWSER_CONTINUE_HUMAN==='1';
 const fromHandback=process.env.BROWSER_CONTINUE_HANDBACK==='1';
 const fromHistory=process.env.BROWSER_CONTINUE_HISTORY==='1';
 const fromProjection=process.env.BROWSER_CONTINUE_PROJECTION==='1';
 const fromReload=process.env.BROWSER_CONTINUE_RELOAD==='1';
 const fromTabs=process.env.BROWSER_CONTINUE_TABS==='1';
 const fromClose=process.env.BROWSER_CONTINUE_CLOSE==='1';
 const selectionChecks=['tab selection restores exact original guest'];
 const selectionReceipt=fromClose?process.env.BROWSER_SELECTION_PREFIX_RECEIPT:null;
 if(fromClose){assert(fromTabs,'close suffix retains all prior native/input/reload receipts');const receipt=JSON.parse(fs.readFileSync(selectionReceipt,'utf8'));assert(selectionChecks.every(name=>receipt.checks.includes(name)),'close suffix requires actual original-guest selection pass');}
 const retainedSelection=fromClose?{receipt:selectionReceipt,checks:selectionChecks}:null;
 const reloadChecks=['toolbar Reload completes in SAME actual guest','Browser reopen after renderer reload restores canonical chrome','Browser reopen after renderer reload re-presents existing guest','profile and tab storage retained across navigation/reload','guest session cookie retained','new tab is a distinct visible native guest'];
 const reloadReceipt=fromTabs?process.env.BROWSER_RELOAD_PREFIX_RECEIPT:null;
 if(fromTabs){assert(fromReload,'tabs suffix retains all prior prefixes');const receipt=JSON.parse(fs.readFileSync(reloadReceipt,'utf8'));assert(reloadChecks.every(name=>receipt.checks.includes(name)),'tabs suffix requires actual six reload/storage/newtab passes');}
 const retainedReload=fromTabs?{receipt:reloadReceipt,checks:reloadChecks,meaning:'Reload RPC/newdoc finished; Browser was explicitly reopened after renderer reload; automatic panel restoration not claimed'}:null;
 const chromeChecks=['canonical Browser tabs and address reflect actual guest'];
 const chromeReceipt=fromReload?process.env.BROWSER_CHROME_PREFIX_RECEIPT:null;
 if(fromReload){assert(fromProjection,'reload suffix retains native history and ownership receipts');const receipt=JSON.parse(fs.readFileSync(chromeReceipt,'utf8'));assert(chromeChecks.every(name=>receipt.checks.includes(name)),'reload suffix requires actual canonical tab/address pass');}
 const retainedChrome=fromReload?{receipt:chromeReceipt,checks:chromeChecks}:null;
 const nativeHistoryChecks=['toolbar Back navigates SAME actual guest','toolbar Forward navigates SAME actual guest'];
 const nativeHistoryReceipt=fromProjection?process.env.BROWSER_NATIVE_HISTORY_RECEIPT:null;
 if(fromProjection){assert(fromHistory,'projection suffix retains prior history setup and receipts');const receipt=JSON.parse(fs.readFileSync(nativeHistoryReceipt,'utf8'));assert(nativeHistoryChecks.every(name=>receipt.checks.includes(name)),'projection suffix requires both actual native Back/Forward passes');}
 const retainedNativeHistory=fromProjection?{receipt:nativeHistoryReceipt,checks:nativeHistoryChecks}:null;
 const historyPrefixChecks=['handback snapshot sees actual human edits','role locator and Enter submit locally','navigation keeps actual guest identity','old document refs refused','refusal does not break fresh snapshots'];
 const historyPrefixReceipt=fromHistory?process.env.BROWSER_HISTORY_PREFIX_RECEIPT:null;
 if(fromHistory){assert(fromHandback,'history suffix retains prior ownership/input receipts');const receipt=JSON.parse(fs.readFileSync(historyPrefixReceipt,'utf8'));assert(historyPrefixChecks.every(name=>receipt.checks.includes(name)),'history suffix requires actual five passed handback/navigation checks');}
 const retainedHistory=fromHistory?{receipt:historyPrefixReceipt,checks:historyPrefixChecks}:null;
 const inputPrefixChecks=['native human character keydowns pass ownership guard after Select All','trusted native human input changes SAME document'];
 const inputPrefixReceipt=fromHandback?process.env.BROWSER_INPUT_PREFIX_RECEIPT:null;
 if(fromHandback){
  assert(fromHuman,'handback suffix retains prior native and takeover/refusal prefixes');
  const receipt=JSON.parse(fs.readFileSync(inputPrefixReceipt,'utf8'));
  assert(inputPrefixChecks.every(name=>receipt.checks.includes(name)),'handback suffix requires actual trusted same-document input receipt');
  const observation=JSON.parse(fs.readFileSync(path.join(path.dirname(inputPrefixReceipt),'human-input-observation.json'),'utf8'));
  assert(observation.immediatePredicate===true&&observation.settledPredicate===true,'retain exact immediate and settled human-input evidence');
 }
 const retainedInput=fromHandback?{receipt:inputPrefixReceipt,checks:inputPrefixChecks}:null;
 const humanPrefixChecks=['takeover consumes its click','bot click refused while human owns page','bot evaluation refused while human owns page'];
 const humanPrefixReceipt=fromHuman?process.env.BROWSER_HUMAN_PREFIX_RECEIPT:null;
 if(fromHuman){assert(fromTakeover,'human suffix also retains original native prefix');const receipt=JSON.parse(fs.readFileSync(humanPrefixReceipt,'utf8'));assert(humanPrefixChecks.every(name=>receipt.checks.includes(name)),'human suffix requires actual takeover/refusal prefix');}
 const retainedHuman=fromHuman?{receipt:humanPrefixReceipt,checks:humanPrefixChecks}:null;
 const retainedPrefix=fromTakeover?JSON.parse(fs.readFileSync(process.env.BROWSER_PREFIX_RECEIPT,'utf8')):null;
 const prefixChecks=['native snapshot carries actual page and PNG','visible sandboxed WebContentsView, no iframe','bot ref input reaches the visible native document','bot scroll uses actual native page'];
 if(retainedPrefix)assert(prefixChecks.every(name=>retainedPrefix.checks.includes(name)),'continuation requires actual retained native prefix');
 const retained=retainedPrefix?{receipt:process.env.BROWSER_PREFIX_RECEIPT,checks:prefixChecks}:null;
 const site=await controlledBrowserPage(),checks=[];
 let guestId=null,phase='setup';
 const ownership={native:[],renderer:[]},wire={frames:[],decodeErrors:0};
 const historyObservation={};
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
 // Wait for the ordinary toolbar reply before replacing its renderer/socket.
 // The observer records the actual authenticated RPC; it never resends one.
 function toolbarReply(command){
  const earlier=new Set(wire.frames.filter(f=>f.direction==='sent'&&f.method==='bots.browser').map(f=>f.id));
  return new Promise((resolve,reject)=>{
   let timer;
   const cleanup=()=>{clearTimeout(timer);wireTap.off('Network.webSocketFrameSent',observe);wireTap.off('Network.webSocketFrameReceived',observe);};
   const observe=()=>{
    const sent=wire.frames.findLast(f=>f.direction==='sent'&&f.method==='bots.browser'&&f.op==='toolbar'&&f.command===command&&f.ownerMatches===true&&!earlier.has(f.id));
    if(!sent)return;
    const reply=wire.frames.find(f=>f.direction==='received'&&f.type==='reply'&&f.id===sent.id);
    if(!reply)return;
    cleanup();
    if(reply.ok!==true)reject(Error(`Toolbar ${command} failed: ${reply.errorText||'RPC refused'}`));
    else resolve({command,id:sent.id,ok:reply.ok});
   };
   timer=setTimeout(()=>{cleanup();reject(Error(`Toolbar ${command} RPC did not settle`));},4000);
   wireTap.on('Network.webSocketFrameSent',observe);wireTap.on('Network.webSocketFrameReceived',observe);observe();
  });
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
 const geometry=async()=>({
  native:await app.evaluate(({BrowserWindow})=>{const w=BrowserWindow.getAllWindows().find(w=>!w.isDestroyed());return{content:w.getContentBounds(),window:w.getBounds(),zoom:w.webContents.getZoomFactor(),focused:w.isFocused(),views:w.contentView.children.filter(v=>v.webContents).map(v=>({id:v.webContents.id,bounds:v.getBounds(),visible:v.getVisible()}))};}),
  renderer:await page.evaluate(()=>{const node=document.querySelector('[data-desktop-browser-owner]'),r=node?.getBoundingClientRect();return{width:innerWidth,height:innerHeight,dpr:devicePixelRatio,surface:r?{x:r.x,y:r.y,width:r.width,height:r.height}:null};})
 });
 const humanClick=async(id,selector)=>app.evaluate(async({webContents},{id,selector})=>{
  const wc=webContents.fromId(id),point=await wc.executeJavaScript(`(()=>{const element=document.querySelector(${JSON.stringify(selector)}),r=element.getBoundingClientRect(),x=Math.round(r.x+r.width/2),y=Math.round(r.y+r.height/2);if(x<0||y<0||x>=innerWidth||y>=innerHeight||!element.contains(document.elementFromPoint(x,y)))throw Error('Fixture human target is outside visible guest viewport');return{x,y}})()`);
  wc.sendInputEvent({type:'mouseDown',button:'left',clickCount:1,...point});wc.sendInputEvent({type:'mouseUp',button:'left',clickCount:1,...point});
 },{id,selector});
 const historyNative=()=>app.evaluate(({BrowserWindow,webContents},id)=>{
  const w=BrowserWindow.getAllWindows().find(w=>!w.isDestroyed()),wc=webContents.fromId(id);
  const current={window:w?{content:w.getContentBounds(),focused:w.isFocused()}:null,guestAlive:!!wc&&!wc.isDestroyed(),events:w?.__sharedBrowserHistory?.events||[],privateFrames:w?.__sharedBrowserPrivateHistory?.frames||[]};
  if(current.guestAlive)Object.assign(current,{url:wc.getURL(),title:wc.getTitle(),focused:wc.isFocused(),loading:wc.isLoadingMainFrame(),zoom:wc.getZoomFactor(),history:wc.navigationHistory.getAllEntries().map(({url,title})=>({url,title})),index:wc.navigationHistory.getActiveIndex(),canBack:wc.navigationHistory.canGoBack(),canForward:wc.navigationHistory.canGoForward()});
  return current;
 },guestId);
 async function saveHistory(label){historyObservation[label]=await historyNative();historyObservation.wire=wire.frames.slice(-40);fs.writeFileSync(path.join(out,'history-observation.json'),JSON.stringify(historyObservation,null,2)+'\n');}
 // Bounded read-only observation of the actual presentation, with an
 // explicit non-empty result and immediate failure for a retired original.
 const waitPresented=(id,closedId=null)=>app.evaluate(async({BrowserWindow,webContents},{id,closedId,siteOrigin})=>new Promise(resolve=>{
  const started=Date.now();function observe(){
   const w=BrowserWindow.getAllWindows().find(w=>!w.isDestroyed()),wc=webContents.fromId(id),closed=closedId==null||!webContents.fromId(closedId)||webContents.fromId(closedId).isDestroyed();
   const shown=(w?.contentView.children||[]).filter(v=>v.webContents&&!v.webContents.isDestroyed()&&v.getVisible()&&v.webContents.getURL().startsWith(siteOrigin)).map(v=>({id:v.webContents.id,url:v.webContents.getURL(),bounds:v.getBounds()}));
   const alive=!!wc&&!wc.isDestroyed(),ok=alive&&closed&&shown.length===1&&shown[0].id===id&&shown[0].bounds.width>100&&shown[0].bounds.height>80;
   if(ok||!alive||Date.now()-started>=4000){resolve({ok,alive,closed,shown});return;}setTimeout(observe,16);
  }observe();
 }),{id,closedId,siteOrigin:site.origin});
 const tabsObservation={};
 async function saveTabs(label,extra={}){
  tabsObservation[label]={...extra,at:Date.now(),native:await native(),renderer:await page.evaluate(()=>({thread:document.querySelector('main')?.dataset.thread,tabs:[...document.querySelectorAll('[data-on-click="br-select"]')].map(n=>({id:n.dataset.value,title:n.textContent,active:n.closest('.browser-tab')?.classList.contains('on')})),status:document.querySelector('.desktop-browser-status')?.textContent})),original:await historyNative(),wire:wire.frames.slice(-24)};
  fs.writeFileSync(path.join(out,'tabs-observation.json'),JSON.stringify(tabsObservation,null,2)+'\n');
 }
 const waitNativeHistory=suffix=>app.evaluate(async({webContents},{id,suffix})=>new Promise(resolve=>{
  const start=Date.now();function observe(){const wc=webContents.fromId(id);if(!wc||wc.isDestroyed()){resolve(false);return;}if(wc.getURL().endsWith(suffix)&&!wc.isLoadingMainFrame()){resolve(true);return;}if(Date.now()-start>=4000){resolve(false);return;}setTimeout(observe,16);}observe();
 }),{id:guestId,suffix});
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
   wire.frames.push({direction,id:o.id,type:o.t,method:o.m,action:p.action,ownerMatches:o.m==='bots.browser'?p.bot===threadId:['tk-takeover','tk-handback'].includes(p.action)?p.value===threadId:undefined,op:o.m==='bots.browser'?p.op:undefined,ok:o.ok,errorCode:typeof o.error==='object'?o.error?.code:undefined,errorText:typeof o.error==='string'?o.error.slice(0,400):undefined,command:o.m==='bots.browser'?p.command:undefined,requestRevision:p.requestRevision??r.requestRevision,viewRevision:o.viewRevision??r.viewRevision,takeover,handback,methods});
  }catch{wire.decodeErrors++;}};
  wireTap.on('Network.webSocketFrameSent',e=>record('sent',e));wireTap.on('Network.webSocketFrameReceived',e=>record('received',e));await wireTap.send('Network.enable');
  await page.waitForFunction(async()=>window.backplaneDesktop?.browser&&(await window.backplaneDesktop.browser.state()).phase==='ready');
  // Playwright's renderer-only viewport can exceed the actual native window.
  // Native guests are correctly clamped to that window; use real desktop
  // geometry for this isolated fixture instead of an emulated 1440px page.
  const windowGeometry={before:await geometry()};
  const saveGeometry=()=>fs.writeFileSync(path.join(out,'native-window-geometry.json'),JSON.stringify(windowGeometry,null,2)+'\n');
  saveGeometry();
  const requested=page.viewportSize()||{width:1440,height:960};
  await app.evaluate(({BrowserWindow},size)=>{const w=BrowserWindow.getAllWindows().find(w=>!w.isDestroyed());w.setContentSize(size.width,size.height);},requested);
  await wireTap.send('Emulation.clearDeviceMetricsOverride');
  windowGeometry.afterResize=await geometry();saveGeometry();
  const content=await app.evaluate(({BrowserWindow})=>{const w=BrowserWindow.getAllWindows().find(w=>!w.isDestroyed());return{...w.getContentBounds(),zoom:w.webContents.getZoomFactor()};});
  // The compositor may constrain native windows. Match Playwright's own
  // viewport override to the measured native content instead of assuming
  // our requested size or a different CDP session's override took effect.
  await page.setViewportSize({width:Math.round(content.width/content.zoom),height:Math.round(content.height/content.zoom)});
  windowGeometry.alignmentStrategy='renderer viewport matches measured native content / zoom';
  await page.waitForFunction(({width,height,zoom})=>Math.abs(innerWidth*zoom-width)<=2&&Math.abs(innerHeight*zoom-height)<=2,content,{timeout:4000});
  windowGeometry.aligned=await geometry();saveGeometry();
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
  if(fromHistory){
   // Fresh native document/history setup only. The retained human, handback,
   // form and stale-ref acceptance checks are not replayed.
   await tool('preview_navigate',{url:site.origin+'/two',readiness:'domContentLoaded'});
   await tool('preview_wait_for',{url:'/two',text:'Shared Browser two'});
  }else{
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
  if(!fromHuman)check('takeover consumes its click',(await inspect(id)).count===beforeHuman.count);
  phase='human';
  if(!fromHuman)check('bot click refused while human owns page',(await tool('preview_click',{selector:'#count'},threadId,true)).isError===true);
  if(!fromHuman)check('bot evaluation refused while human owns page',(await tool('preview_evaluate',{expression:'window.fixtureState.count++'},threadId,true)).isError===true);
  // The renderer's person strip and main's native grant travel separately.
  // Wait for the actual guest presentation with its shield removed; no input
  // is sent until the native authority transition is visible.
  await app.evaluate(async({BrowserWindow},{id})=>new Promise((resolve,reject)=>{
   const start=Date.now();function observe(){
    const w=BrowserWindow.getAllWindows().find(w=>!w.isDestroyed()),views=w?.contentView.children||[];
    if(views.some(v=>v.webContents?.id===id&&v.getVisible()&&v.getBounds().width>100&&v.getBounds().height>80)&&!views.some(v=>v.getVisible()&&v.webContents?.getURL().endsWith('/browser-shield.html'))){resolve();return;}
    if(Date.now()-start>=4000){reject(Error('Native human presentation did not become ready'));return;}setTimeout(observe,16);
   }observe();
  }),{id});
  windowGeometry.beforeHuman=await geometry();saveGeometry();
  // A fresh isolated page needs its own real human edit for the pending
  // handback snapshot. In handback-only mode this is setup, not a replayed
  // acceptance claim: the two human checks remain bound to their old receipt.
  const humanInput={initial,beforeHuman,geometry:windowGeometry.beforeHuman,setupOnly:fromHandback};
  const saveHuman=()=>fs.writeFileSync(path.join(out,'human-input-observation.json'),JSON.stringify(humanInput,null,2)+'\n');
  // Native input is sent once. Main's sendInputEvent returning is not an
  // acknowledgement that Chromium's renderer has processed that input.
  await app.evaluate(({webContents},id)=>{
   const wc=webContents.fromId(id),probe={events:[]};wc.__sharedBrowserHuman=probe;
   for(const name of ['before-input-event','before-mouse-event'])wc.on(name,(event,input)=>{if(probe.events.length<64)probe.events.push({event:name,type:input?.type,key:input?.key,control:input?.control,meta:input?.meta,shift:input?.shift,button:input?.button,prevented:event.defaultPrevented===true});});
  },id);
  saveHuman();
  await humanClick(id,'#entry');
  humanInput.afterEntryClick=await inspect(id);saveHuman();
  await app.evaluate(({webContents},id)=>{
   const wc=webContents.fromId(id);wc.focus();
   wc.sendInputEvent({type:'keyDown',keyCode:'A',modifiers:[process.platform==='darwin'?'meta':'control']});wc.sendInputEvent({type:'keyUp',keyCode:'A',modifiers:[process.platform==='darwin'?'meta':'control']});
   // A handled shortcut makes Chromium suppress Char/KeyUp until the
   // next RawKeyDown. Model complete physical keystrokes after Select All,
   // rather than sending orphan Char events that belong to the shortcut.
   for(const character of 'human typed'){
    const keyCode=character===' '?'Space':character;
    wc.sendInputEvent({type:'keyDown',keyCode,modifiers:[]});
    wc.sendInputEvent({type:'char',keyCode:character,modifiers:[]});
    wc.sendInputEvent({type:'keyUp',keyCode,modifiers:[]});
   }
  },id);
  humanInput.afterTyping=await inspect(id);saveHuman();
  await humanClick(id,'#count');
  humanInput.immediate=await inspect(id);
  const matchesHuman=value=>value.document===initial.document&&value.entry==='human typed'&&value.count===beforeHuman.count+1&&value.trustedClicks===beforeHuman.trustedClicks+1&&value.trustedInputs>beforeHuman.trustedInputs;
  humanInput.immediatePredicate=matchesHuman(humanInput.immediate);saveHuman();
  // Bounded read-only observation; no click, key, script event or input retry.
  // Keep the immediate result separately even if renderer settlement differs.
  humanInput.processing=await app.evaluate(async({webContents},{id,expectedCount})=>webContents.fromId(id).executeJavaScript(`new Promise(resolve=>{
   const started=performance.now();
   function observe(){
    const ready=document.querySelector('#entry').value==='human typed'&&fixtureState.count===${expectedCount};
    if(ready||performance.now()-started>=4000){resolve({ready,elapsedMs:performance.now()-started});return;}
    setTimeout(observe,16);
   }observe();
  })`),{id,expectedCount:beforeHuman.count+1});
  const human=await inspect(id);
  humanInput.human=human;humanInput.settledPredicate=matchesHuman(human);
  humanInput.native=await app.evaluate(({webContents},id)=>webContents.fromId(id).__sharedBrowserHuman,id);saveHuman();
  if(!fromHandback){
  const keyDowns=humanInput.native.events.filter(e=>e.event==='before-input-event'&&e.type==='keyDown');
  const plainKeyDowns=keyDowns.filter(e=>!e.control&&!e.meta);
  check('native human character keydowns pass ownership guard after Select All',plainKeyDowns.length==='human typed'.length&&plainKeyDowns.every(e=>!e.prevented));
  check('trusted native human input changes SAME document',human.document===initial.document&&human.entry==='human typed'&&human.count===beforeHuman.count+1&&human.trustedClicks===beforeHuman.trustedClicks+1&&human.trustedInputs>beforeHuman.trustedInputs);
  }
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
  }
  phase='history';
  // UI address/history/reload use the same service intent pipeline.
  await app.evaluate(({BrowserWindow,webContents},id)=>{
   const w=BrowserWindow.getAllWindows().find(w=>!w.isDestroyed()),wc=webContents.fromId(id),probe={events:[]};w.__sharedBrowserHistory=probe;
   for(const name of ['will-navigate','did-start-navigation','did-navigate','did-navigate-in-page','dom-ready','did-finish-load','did-fail-load','render-process-gone','destroyed'])wc.on(name,()=>{if(probe.events.length<80)probe.events.push({event:name,at:Date.now(),destroyed:wc.isDestroyed(),url:wc.isDestroyed()?null:wc.getURL()});});
   wc.debugger.on('detach',(_event,reason)=>{if(probe.events.length<80)probe.events.push({event:'debugger-detach',reason,at:Date.now()});});
  },id);
  if(fromHistory)await app.evaluate(({app,BrowserWindow})=>{
   // Observe only this existing private transport in the isolated fixture.
   // Forward every original call/argument unchanged. No authority, endpoint,
   // payload or product file is modified; never retain tokens/body/opaque state.
   const w=BrowserWindow.getAllWindows().find(w=>!w.isDestroyed()),probe={frames:[]};w.__sharedBrowserPrivateHistory=probe;
   const {createRequire}=process.getBuiltinModule('module'),load=createRequire(app.getAppPath()+'/main.cjs'),WS=load('ws');
   const proto=WS.prototype,send=proto.send,emit=proto.emit,terminate=proto.terminate;
   const target=value=>value&&typeof value==='object'?{owner:value.owner,tabId:value.tabId,generation:value.generation}:null;
   const add=value=>{if(probe.frames.length>=128)probe.frames.shift();probe.frames.push({at:Date.now(),...value});};
   const isPrivate=socket=>{try{return new URL(socket.url).pathname==='/desktop/browser/v1';}catch{return false;}};
   const record=(socket,direction,data)=>{try{
    if(!isPrivate(socket))return;
    const m=JSON.parse(typeof data==='string'?data:data.toString('utf8')),p=m.payload||{};
    add({direction,op:m.op,id:m.id,serverSequence:m.serverSequence,clientSequence:m.clientSequence,owner:p.owner,revision:p.revision,grantRevision:p.grantRevision,resultRevision:p.resultRevision,target:target(p.target),fromTarget:target(p.fromTarget),dispatchTarget:target(p.dispatchTarget),operation:p.op,drive:p.drive,scope:p.scope,reply:p.reply?{ok:p.reply.ok,dispatched:p.reply.dispatched,error:typeof p.reply.error==='string'?p.reply.error.slice(0,400):undefined}:undefined,ok:p.ok,error:typeof p.error==='string'?p.error.slice(0,400):undefined,event:p.event?{type:p.event.type,owner:p.event.owner,tabId:p.event.tabId,generation:p.event.generation}:undefined});
   }catch{add({direction,decodeError:true});}};
   proto.send=function(data,...args){record(this,'sent',data);return send.call(this,data,...args);};
   proto.emit=function(name,...args){if(name==='message')record(this,'received',args[0]);return emit.call(this,name,...args);};
   proto.terminate=function(...args){if(isPrivate(this))add({direction:'terminate',stack:new Error('Fixture private Browser termination boundary').stack.split('\n').slice(0,12).join('\n')});return terminate.apply(this,args);};
  });
  if(!fromProjection){
  await saveHistory('beforeBack');
  await page.locator('[data-on-click="br-back"]').first().click();
  const backReady=await waitNativeHistory('/one');await saveHistory('afterBack');
  check('toolbar Back navigates SAME actual guest',backReady);
  await page.waitForFunction(async()=>document.querySelector('.browser-tab.on')?.textContent.includes('one'));
  await page.locator('[data-on-click="br-forward"]').first().click();
  const forwardReady=await waitNativeHistory('/two');await saveHistory('afterForward');
  check('toolbar Forward navigates SAME actual guest',forwardReady);
  await page.waitForFunction(()=>document.querySelector('.browser-tab.on')?.textContent.includes('two'));
  }
  // Keep the failed actual title requirement and also check its address.
  // Continuation opens one -> two solely as fresh setup; no settled history
  // toolbar input or acceptance is replayed.
  await page.waitForFunction(owner=>document.querySelector('.browser-tab.on')?.textContent.includes('two')&&document.querySelector(`[data-bfield="brurl:${owner}"]`)?.value.endsWith('/two'),threadId);
  if(!fromReload)check('canonical Browser tabs and address reflect actual guest',(await inspect(id))!=null&&(await native()).some(v=>v.id===id&&v.url.endsWith('/two')));
  phase='remaining-browser';
  if(!fromTabs){
  const beforeReload=await inspect(id);
  const [reloadRpc]=await Promise.all([toolbarReply('reload'),page.locator('[data-on-click="br-reload"]').first().click()]);
  const reloaded=await app.evaluate(async({webContents},{id,document})=>new Promise(resolve=>{
   const started=Date.now();
   async function observe(){
    const wc=webContents.fromId(id);
    if(!wc||wc.isDestroyed()){resolve(false);return;}
    try{const current=await wc.executeJavaScript('typeof fixtureState!=="undefined"?fixtureState.document:null');if(typeof current==='string'&&current!==document&&!wc.isLoadingMainFrame()&&wc.getURL().endsWith('/two')){resolve(true);return;}}catch{}
    if(Date.now()-started>=4000){resolve(false);return;}setTimeout(observe,16);
   }observe();
  }),{id,document:beforeReload.document});
  historyObservation.reloadRpc=reloadRpc;await saveHistory('afterToolbarReload');
  check('toolbar Reload completes in SAME actual guest',reloaded);
  await page.reload();
  await page.waitForFunction(()=>document.documentElement.dataset.backplaneRemoteReady==='true');
  // Thread viewer choice is connection-local actor state, not a persisted
  // thread/bot route. Reopen Browser with its real visible UI action, without
  // navigating, recreating, or obtaining a new guest before the identity check.
  await page.locator('[data-on-click="view-kind"][data-value="browser"]').first().click();
  await page.locator(`[data-desktop-browser-owner="${threadId}"]`).waitFor();
  await page.waitForFunction(owner=>document.querySelector('.browser-tab.on')?.textContent.includes('two')&&document.querySelector(`[data-bfield="brurl:${owner}"]`)?.value.endsWith('/two'),threadId);
  check('Browser reopen after renderer reload restores canonical chrome',await page.locator('[data-on-click="br-select"]').count()===1);
  const retained=(await native()).find(v=>v.id===id);
  check('Browser reopen after renderer reload re-presents existing guest',retained?.visible===true);
  const after=await inspect(id);
  check('profile and tab storage retained across navigation/reload',initial.profile===after.profile&&initial.tab===after.tab);
  await app.evaluate(async({webContents},id)=>{await webContents.fromId(id).session.cookies.flushStore();},id);
  check('guest session cookie retained',await app.evaluate(async({webContents},{id,url})=>(await webContents.fromId(id).session.cookies.get({url,name:'fixtureSession'})).length===1,{id,url:site.origin}));
  }
  const originalTab=await page.locator('[data-on-click="br-select"]').first().getAttribute('data-value');
  await page.locator('[data-on-click="br-new"]').first().click();
  await page.waitForFunction(()=>document.querySelectorAll('[data-on-click="br-select"]').length===2);
  const newTab=await page.locator('[data-on-click="br-select"]').last().getAttribute('data-value');
  const address=page.locator(`[data-bfield="brurl:${threadId}"]`);
  await address.fill(site.origin+'/one');await page.locator('[data-on-click="br-go"]').first().click();
  await page.waitForFunction(()=>document.querySelector('.browser-tab.on')?.textContent.includes('one'));
  const newGuest=(await native()).find(v=>v.id!==id&&v.visible&&v.url.endsWith('/one'));
  assert(newGuest,'fresh two-tab setup has its distinct visible native guest');
  if(!fromTabs)check('new tab is a distinct visible native guest',!!newGuest);
  phase='tabs';await saveTabs('beforeSelect');
  const [selectRpc]=await Promise.all([toolbarReply('tabs'),page.locator(`[data-on-click="br-select"][data-value="${originalTab}"]`).click()]);
  await saveTabs('afterSelectRpc',{selectRpc});
  await page.waitForFunction(tab=>document.querySelector('.browser-tab.on [data-on-click="br-select"]')?.dataset.value===tab,originalTab,{timeout:4000});
  const selected=await waitPresented(id);await saveTabs('afterSelect',{selectRpc,presentation:selected});
  if(fromClose)assert(selected.ok,'fresh setup selects the original guest before closing its inactive sibling');
  if(!fromClose)check('tab selection restores exact original guest',selected.ok&&(await native()).find(v=>v.id===id)?.visible===true);
  const [closeRpc]=await Promise.all([toolbarReply('tabs'),page.locator(`[data-on-click="br-close"][data-value="${newTab}"]`).click()]);
  await saveTabs('afterCloseRpc',{closeRpc});
  await page.waitForFunction(tab=>document.querySelectorAll('[data-on-click="br-select"]').length===1&&document.querySelector('.browser-tab.on [data-on-click="br-select"]')?.dataset.value===tab,originalTab,{timeout:4000});
  const closed=await waitPresented(id,newGuest.id);await saveTabs('afterClose',{closeRpc,presentation:closed});
  check('closing other tab preserves original guest and retires closed guest',closed.ok);
  await page.locator(`[data-on-click="tk-handback"][data-value="${threadId}"]`).click();
  await page.locator(`[data-on-click="tk-takeover"][data-value="${threadId}"]`).waitFor();
  check('preview follows user-selected tab',(await tool('preview_snapshot')).value.title==='Shared Browser two');
  if(otherThreadId){
   await select(otherThreadId);await tool('preview_open',{url:site.origin+'/two'},otherThreadId);
   await select(threadId);
   const returned=await waitPresented(id);await saveTabs('afterThreadSwitch',{presentation:returned});
   check('thread switch restores its actual guest',returned.ok&&(await native()).filter(v=>v.visible).length===1&&(await native()).find(v=>v.id===id)?.visible===true);
  }
  await page.screenshot({path:path.join(out,'shared-browser-chrome.png')});
  const pixels=await app.evaluate(async({webContents},id)=>(await webContents.fromId(id).capturePage()).toPNG().toString('base64'),id);
  fs.writeFileSync(path.join(out,'shared-browser-guest.png'),Buffer.from(pixels,'base64'));
  const receipt={status:'PASS',checks,retainedPrefix:retained,retainedHumanPrefix:retainedHuman,retainedInputPrefix:retainedInput,retainedHistoryPrefix:retainedHistory,retainedNativeHistory,retainedChrome,retainedReload,retainedSelection,guestId:id,scope:'Actual Electron native guest + authenticated preview MCP + trusted human input; isolated controlled local page only',remaining:['physical manual input/IME','full Electron exit/relaunch cookie and tab restoration','remote machine browser attachment/reconnect','popup adoption (current guest policy denies unqualified popups)']};
  fs.writeFileSync(path.join(out,'shared-browser.json'),JSON.stringify(receipt,null,2)+'\n');
  return receipt;
 }catch(error){
  if(phase==='tabs')try{await saveTabs('failure');}catch(e){tabsObservation.captureError=e.message;fs.writeFileSync(path.join(out,'tabs-observation.json'),JSON.stringify(tabsObservation,null,2)+'\n');}
  if(phase==='history'||phase==='remaining-browser')try{await saveHistory('failure');}catch(e){historyObservation.captureError=e.message;fs.writeFileSync(path.join(out,'history-observation.json'),JSON.stringify(historyObservation,null,2)+'\n');}
  // Retain this exact failure boundary before another helper changes the UI.
  try{ownership.renderer=await page.evaluate(()=>({events:window.__sharedBrowserTakeover?.events||[],remoteReady:document.documentElement.dataset.backplaneRemoteReady,thread:document.querySelector('main')?.dataset.thread,strip:document.querySelector('.desktop-browser-drive')?.textContent,controls:[...document.querySelectorAll('.desktop-browser-drive [data-on-click]')].map(n=>({action:n.dataset.onClick,value:n.dataset.value})),status:document.querySelector('.desktop-browser-status')?.textContent}));}catch(e){ownership.rendererError=e.message;}
  try{ownership.native=await app.evaluate(({BrowserWindow,webContents},id)=>{const w=BrowserWindow.getAllWindows().find(w=>!w.isDestroyed());return{probe:w?.__sharedBrowserOwnership,windowFocused:w?.isFocused(),focusedId:webContents.getFocusedWebContents()?.id??null,views:w?.contentView.children.filter(v=>v.webContents).map(v=>({id:v.webContents.id,url:v.webContents.getURL(),visible:v.getVisible(),bounds:v.getBounds(),guest:v.webContents.id===id}))};},guestId);}catch(e){ownership.nativeError=e.message;}
  if(phase==='takeover'||phase==='handback')try{const probe=await tool('preview_snapshot',{},threadId,true);ownership.canonicalSnapshotProbe={isError:probe.isError,text:probe.content?.find(c=>c.type==='text')?.text?.slice(0,400)};}catch(e){ownership.canonicalProbeError=e.message;}
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
  fs.writeFileSync(path.join(out,'shared-browser.json'),JSON.stringify({status:'FAIL',checks,retainedPrefix:retained,retainedHumanPrefix:retainedHuman,retainedInputPrefix:retainedInput,retainedHistoryPrefix:retainedHistory,retainedNativeHistory,retainedChrome,retainedReload,retainedSelection,phase,error:error.stack,scope:'No deployment acceptance claimed'},null,2)+'\n');throw error;
 }
 finally{if(wireTap)await wireTap.detach().catch(()=>{});await site.close();}
}
module.exports={controlledBrowserPage,runSharedBrowserAcceptance};
