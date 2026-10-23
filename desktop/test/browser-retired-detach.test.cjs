'use strict';
// Actual guest event producer + actual document lifecycle consumer. Native
// close ordering is simulated; the sole controller owns Electron acceptance.
const {test}=require('node:test'),assert=require('node:assert/strict'),{EventEmitter}=require('node:events');
const {createBrowserGuestManager}=require('../browser-guest.cjs');
const {createGuestDocuments}=require('../browser-documents.cjs');
async function fixture({synchronousDetach=false}={}){
 let allowed=true;const events=[],views=[],children=[],registryErrors=[];const documents=createGuestDocuments();
 const ses=Object.assign(new EventEmitter(),{getPreloadScripts:()=>[],webRequest:{onBeforeRequest(){}},setPermissionRequestHandler(){},setPermissionCheckHandler(){}});
 const window=Object.assign(new EventEmitter(),{isDestroyed:()=>false,getContentBounds:()=>({width:800,height:600}),
  contentView:{children,addChildView(v){if(!children.includes(v))children.push(v);},removeChildView(v){const at=children.indexOf(v);if(at>=0)children.splice(at,1);}},webContents:{isDestroyed:()=>false,focus(){}}});
 class View{
  constructor({webPreferences}){
   this.visible=false;this.rect={x:0,y:0,width:100,height:100};let destroyed=false,attached=false;
   const wc=Object.assign(new EventEmitter(),{session:webPreferences.session,loadURL:async()=>{},isDestroyed:()=>destroyed,isFocused:()=>false,
    setWindowOpenHandler(){},setIgnoreMenuShortcuts(){},focus(){},close(){const detached=()=>{attached=false;this.debugger.emit('detach',{},'target closed');};if(synchronousDetach)detached();destroyed=true;this.emit('destroyed');if(!synchronousDetach)queueMicrotask(detached);}});
   wc.debugger=Object.assign(new EventEmitter(),{isAttached:()=>attached,attach(){attached=true;},sendCommand:async()=>({})});this.webContents=wc;views.push(this);
  }
  setVisible(value){this.visible=value;}getVisible(){return this.visible;}
  setBounds(value){this.rect={...value};}getBounds(){return{...this.rect};}
 }
 const manager=createBrowserGuestManager({electron:{WebContentsView:View,session:{fromPartition:()=>ses}},window,appSession:{},trustedOrigins:['http://127.0.0.1:12345'],authorize:()=>allowed,onEvent:event=>{events.push(event);try{documents.observe(event);}catch(error){registryErrors.push(error.message);}}});
 const a=await manager.create({owner:'review',createId:'fixture-a'}),b=await manager.create({owner:'review',createId:'fixture-b'});
 manager.completeCreation({owner:'review',createId:'fixture-a',target:a});manager.completeCreation({owner:'review',createId:'fixture-b',target:b});
 events.length=0;
 return{manager,a,b,views,events,registryErrors,deny(){allowed=false;},allow(){allowed=true;},get inventory(){return events.filter(e=>e.type==='tabs');}};
}
const rect={x:0,y:0,width:400,height:300};
for(const synchronousDetach of [false,true])test(`expected close emits one retirement with ${synchronousDetach?'synchronous':'trailing'} native detach`,async()=>{
 const h=await fixture({synchronousDetach});try{
  h.manager.present(h.a,rect);h.manager.close(h.b);await Promise.resolve();
  assert.equal(h.events.filter(e=>e.type==='closed'&&e.tabId===h.b.tabId).length,1);
  assert.equal(h.events.filter(e=>e.type==='debugger-detached'&&e.tabId===h.b.tabId).length,0);
  assert.deepEqual(h.registryErrors,[],'a retired target is never delivered twice to the real document registry');
  assert.equal(h.views[1].webContents.isDestroyed(),true);assert.throws(()=>h.manager.present(h.b,rect));
  h.manager.present(h.a,rect);assert.equal(h.views[0].getVisible(),true);assert.equal(h.manager.list('review').length,1);
 }finally{h.manager.dispose();await Promise.resolve();}
});
test('unexpected debugger detach on live guest still loses guard and retires document authority',async()=>{
 const h=await fixture();try{
  h.manager.present(h.a,rect);h.views[0].webContents.debugger.emit('detach',{},'unexpected live detach');
  assert.equal(h.events.filter(e=>e.type==='file-guard-lost'&&e.tabId===h.a.tabId).length,1);
  assert.equal(h.events.filter(e=>e.type==='debugger-detached'&&e.tabId===h.a.tabId).length,1);
  assert.equal(h.events.filter(e=>e.type==='closed'&&e.tabId===h.a.tabId).length,0);
  assert.deepEqual(h.registryErrors,[]);assert.equal(h.views[0].webContents.isDestroyed(),false);
  assert.throws(()=>h.manager.present(h.a,rect),error=>error.code==='GUEST_FILE_GUARD_LOST');
  assert.equal(h.views[0].getVisible(),false);
 }finally{h.manager.dispose();await Promise.resolve();}
});
