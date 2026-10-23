'use strict';
// Focused security regression against the real dispatcher, leases and guest
// event guard. Native views/debugger transport are simulated; the integrator's
// actual Electron/MCP helper remains the native-runtime acceptance gate.
const {test}=require('node:test'),assert=require('node:assert/strict'),{EventEmitter}=require('node:events');
const {createBrowserDispatch,createBrowserUnknownState,consumeBrowserMouse}=require('../browser-dispatch.cjs');
const {createBrowserLeases}=require('../browser-leases.cjs');
const {createBrowserGuestManager}=require('../browser-guest.cjs');
const {createBrowserSurface}=require('../browser-surface.cjs');
const deferred=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return{promise,resolve,reject};};
const params={type:'mousePressed',x:64,y:48,button:'left',clickCount:1};
const mouse=p=>({type:{mouseMoved:'mouseMove',mousePressed:'mouseDown',mouseReleased:'mouseUp'}[p.type],x:p.x,y:p.y,button:p.button,clickCount:p.clickCount});

async function guest(){
 let now=0,boot=true,protectedView=true,wc,dispatch,active,sequence=0;
 const leases=createBrowserLeases({now:()=>now}),unknownState=createBrowserUnknownState();
 const ses=Object.assign(new EventEmitter(),{getPreloadScripts:()=>[],webRequest:{onBeforeRequest(){}},setPermissionRequestHandler(){},setPermissionCheckHandler(){}});
 const children=[];
 const window=Object.assign(new EventEmitter(),{isDestroyed:()=>false,getContentBounds:()=>({width:800,height:600}),
  contentView:{children,addChildView(v){children.push(v);},removeChildView(v){const i=children.indexOf(v);if(i>=0)children.splice(i,1);}},
  webContents:{isDestroyed:()=>false,focus(){}}});
 class View{
  constructor({webPreferences}){
   this.visible=false;this.bounds={x:0,y:0,width:100,height:100};let destroyed=false,attached=false;
   wc=Object.assign(new EventEmitter(),{session:webPreferences.session,loadURL:async()=>{},isDestroyed:()=>destroyed,isFocused:()=>false,
    setWindowOpenHandler(){},setIgnoreMenuShortcuts(){},focus(){},close(){destroyed=true;this.emit('destroyed');}});
   wc.debugger=Object.assign(new EventEmitter(),{isAttached:()=>attached,attach(){attached=true;},sendCommand:async method=>{
    if(method!=='Input.dispatchMouseEvent')return{};
    assert(active,'test owns the captured native command');active.started.resolve();return active.result.promise;
   }});
   this.webContents=wc;
  }
  setVisible(v){this.visible=v;}getVisible(){return this.visible;}
  setBounds(v){this.bounds={...v};}getBounds(){return{...this.bounds};}
 }
 const manager=createBrowserGuestManager({electron:{WebContentsView:View,session:{fromPartition:()=>ses}},window,appSession:{},trustedOrigins:['http://127.0.0.1:12345'],
  authorize:value=>boot||dispatch.authorize(value),agentInputProtected:()=>protectedView});
 const target=await manager.create({owner:'fixture'});
 leases.establish('a'.repeat(32),'b'.repeat(32));leases.receiveSequence(1);leases.observe('created',target,{createId:'bootstrap'});
 leases.ownerGrant({owner:target.owner,revision:1,ttlMs:3000,operations:['list']});
 const grant=(drive,revision)=>leases.targetGrant({target,revision,ttlMs:3000,drive,operations:drive==='agent'?['cdp','present','hide']:['present','hide','direct-input','focus'],
  cdpMethods:drive==='agent'?['Input.dispatchMouseEvent']:[],initializationMethods:[]});
 grant('agent',2);dispatch=createBrowserDispatch({leases,manager,unknownState});boot=false;
 manager.present(target,{x:0,y:0,width:400,height:300});
 const input=(p=mouse(params),event='before-mouse-event')=>{const e={defaultPrevented:false,preventDefault(){this.defaultPrevented=true;}};wc.emit(event,e,p);return e.defaultPrevented;};
 const invoke=(p=params)=>dispatch.invoke({id:(++sequence).toString(16).padStart(32,'0'),target,revision:2,operation:'cdp',method:'Input.dispatchMouseEvent',params:p});
 async function begin(p=params){
  const slot=active={started:deferred(),result:deferred()},answer=invoke(p);
  await Promise.race([slot.started.promise,answer.then(()=>{throw new Error('Native command was not captured');})]);
  return{answer,finish:()=>slot.result.resolve({}),reject:error=>slot.result.reject(error)};
 }
 return{target,leases,dispatch,manager,input,invoke,begin,unknownState,
  expire:()=>{now=3000;},disconnect:()=>leases.clear(),revoke:()=>leases.revoke({scope:'mutation',owner:target.owner,revision:3}),
  navigate:()=>{wc.emit('did-start-navigation',{isMainFrame:true,isSameDocument:false});leases.observe('generation',{...target,generation:target.generation+1});},
  protect:value=>{protectedView=value;},person:()=>{
   leases.revoke({scope:'mutation',owner:target.owner,revision:3});leases.receiveSequence(2);
   leases.ownerGrant({owner:target.owner,revision:4,ttlMs:3000,operations:['list']});grant('person',4);manager.reconcileInput();
  },dispose:()=>{dispatch.close();manager.dispose();}};
}

test('validated CDP mouse events pass once; concurrent unrelated input stays blocked',async()=>{
 const h=await guest();
 try{
  assert.equal(h.input(),true,'human input has no ambient agent permission');
  for(const type of ['mouseMoved','mousePressed','mouseReleased']){
   const p={...params,type,clickCount:type==='mouseMoved'?0:1},event=mouse(p),flight=await h.begin(p);
   assert.equal(h.input({...event,x:event.x+8}),true,'off-target pointer blocked while command waits');
   assert.equal(h.input({...event,button:'right'}),true,'another button cannot borrow the permit');
   assert.equal(h.input({...event,clickCount:event.clickCount+1}),true,'another click count cannot borrow the permit');
   assert.equal(h.input({type:'keyDown'},'before-input-event'),true,'mouse dispatch cannot enable keyboard input');
   assert.equal(h.input(event,'context-menu'),true,'mouse dispatch cannot enable context menu');
   assert.equal(h.input(event),false,'one matching event passes under original fresh authority');
   assert.equal(h.input(event),true,'permit cannot replay');
   flight.finish();await flight.answer;
   assert.equal(h.input(event),true,'completed command cannot authorize later input');
  }
  h.person();assert.equal(h.input(),false,'canonical person grant still admits normal human input');
  await assert.rejects(async()=>h.invoke(),'stale agent grant cannot dispatch after takeover');
 }finally{h.dispose();}
});

test('visible guest needs the actual shield even with a pending authorized command',async()=>{
 const h=await guest();
 try{
  h.protect(false);const flight=await h.begin();assert.equal(h.input(),true,'no bypass on an uncovered native guest');
  h.protect(true);assert.equal(h.input(),false,'same pending permit works after native protection exists');
  flight.finish();await flight.answer;
 }finally{h.dispose();}
});

test('expired, revoked, disconnected, or changed-document grants cannot release pending native input',async()=>{
 for(const invalidate of ['expire','revoke','disconnect','navigate']){
  const h=await guest();
  try{const flight=await h.begin();h[invalidate]();assert.equal(h.input(),true,invalidate+' invalidates before native delivery');flight.finish();await flight.answer;}
  finally{h.dispose();}
 }
});

test('forged permissions and rejected commands do not leave an input allowance',async()=>{
 const h=await guest();
 try{
  assert.equal(consumeBrowserMouse({},h.target,'before-mouse-event',mouse(params),true),false);
  const flight=await h.begin();flight.reject(Object.assign(new Error('rejected before dispatch'),{dispatched:false}));
  await assert.rejects(flight.answer);assert.equal(h.input(),true,'rejection retires the permit');
 }finally{h.dispose();}
});

test('controller shutdown denies native input from an unresolved command',async()=>{
 const h=await guest();
 try{
  const flight=await h.begin(),answer=flight.answer.catch(error=>error);h.dispatch.close();
  assert.equal(h.input(),true);flight.finish();assert.equal((await answer).dispatched,true);assert(h.unknownState.has(h.target.owner));
 }finally{h.dispose();}
});

test('native shield proof is exact, topmost, visible, and removed only by authoritative handoff',()=>{
 const children=[],views=[];let person=false,focuses=0;
 const window=Object.assign(new EventEmitter(),{isDestroyed:()=>false,contentView:{children,addChildView(v){const i=children.indexOf(v);if(i>=0)children.splice(i,1);children.push(v);},removeChildView(v){const i=children.indexOf(v);if(i>=0)children.splice(i,1);}}});
 class View{
  constructor(){this.visible=false;this.rect={};this.webContents=Object.assign(new EventEmitter(),{isDestroyed:()=>false,loadURL:async()=>{},setWindowOpenHandler(){},close(){}});views.push(this);}
  setBackgroundColor(){}setVisible(v){this.visible=v;}getVisible(){return this.visible;}setBounds(v){this.rect={...v};}getBounds(){return{...this.rect};}
 }
 const target={owner:'fixture',tabId:'guest',generation:1},bounds={x:0,y:0,width:400,height:300};
 const manager={list:()=>[{...target,active:true}],present:()=>({bounds,inputAllowed:person}),reconcileInput(){},hide(){},focus(){focuses++;}};
 const surface=createBrowserSurface({electron:{WebContentsView:View,session:{fromPartition:()=>({setPermissionRequestHandler(){},setPermissionCheckHandler(){}})}},window,manager,authorize:value=>value.operation==='direct-input'?person:true,onTakeover(){}});
 try{
  assert.equal(surface.guards(target),false);surface.present({owner:target.owner,bounds});assert.equal(surface.guards(target),true);
  assert.equal(surface.guards({...target,generation:0}),false);assert.equal(surface.guards({...target,owner:'other'}),false);
  children.push({});assert.equal(surface.guards(target),false);surface.refresh();assert.equal(surface.guards(target),true,'refresh restores shield above reattached guest');
  views[0].setVisible(false);assert.equal(surface.guards(target),false);views[0].setVisible(true);
  views[0].setBounds({...bounds,width:200});assert.equal(surface.guards(target),false);views[0].setBounds(bounds);
  person=true;surface.refresh();assert.equal(surface.guards(target),false);assert.equal(focuses,1);
  surface.refresh();assert.equal(focuses,1,'heartbeat cannot steal focus again');
  person=false;surface.refresh();assert.equal(surface.guards(target),true);surface.hide();assert.equal(surface.guards(target),false);
 }finally{surface.dispose();}
});
