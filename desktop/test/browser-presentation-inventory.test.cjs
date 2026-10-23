'use strict';
// New presentation/inventory behavior only, using the actual guest manager.
// Native transport is simulated here; sole-controller Electron tabs suffix
// remains the actual guest/ACK/authority acceptance.
const {test}=require('node:test'),assert=require('node:assert/strict'),{EventEmitter}=require('node:events');
const {createBrowserGuestManager}=require('../browser-guest.cjs');
async function fixture(){
 let allowed=true;const events=[],views=[],children=[];
 const ses=Object.assign(new EventEmitter(),{getPreloadScripts:()=>[],webRequest:{onBeforeRequest(){}},setPermissionRequestHandler(){},setPermissionCheckHandler(){}});
 const window=Object.assign(new EventEmitter(),{isDestroyed:()=>false,getContentBounds:()=>({width:800,height:600}),
  contentView:{children,addChildView(v){if(!children.includes(v))children.push(v);},removeChildView(v){const at=children.indexOf(v);if(at>=0)children.splice(at,1);}},webContents:{isDestroyed:()=>false,focus(){}}});
 class View{
  constructor({webPreferences}){
   this.visible=false;this.rect={x:0,y:0,width:100,height:100};let destroyed=false,attached=false;
   const wc=Object.assign(new EventEmitter(),{session:webPreferences.session,loadURL:async()=>{},isDestroyed:()=>destroyed,isFocused:()=>false,
    setWindowOpenHandler(){},setIgnoreMenuShortcuts(){},focus(){},close(){destroyed=true;this.emit('destroyed');}});
   wc.debugger=Object.assign(new EventEmitter(),{isAttached:()=>attached,attach(){attached=true;},sendCommand:async()=>({})});this.webContents=wc;views.push(this);
  }
  setVisible(value){this.visible=value;}getVisible(){return this.visible;}
  setBounds(value){this.rect={...value};}getBounds(){return{...this.rect};}
 }
 const manager=createBrowserGuestManager({electron:{WebContentsView:View,session:{fromPartition:()=>ses}},window,appSession:{},trustedOrigins:['http://127.0.0.1:12345'],authorize:()=>allowed,onEvent:event=>events.push(event)});
 const a=await manager.create({owner:'review'}),b=await manager.create({owner:'review'});
 events.length=0;
 return{manager,a,b,views,events,deny(){allowed=false;},allow(){allowed=true;},get inventory(){return events.filter(e=>e.type==='tabs');}};
}
const rect={x:0,y:0,width:400,height:300};
test('same active guest presentation, hide/show and geometry changes emit no false inventory',async()=>{
 const h=await fixture();try{
  assert(h.manager.list('review').find(t=>t.tabId===h.a.tabId).active);
  h.manager.present(h.a,rect);h.manager.hide();h.manager.present(h.a,rect);h.manager.present(h.a,{...rect,width:420});
  assert.equal(h.inventory.length,0,'no old-revision registry RPC from re-presentation');
  assert.equal(h.views[0].getVisible(),true);assert.equal(h.views[0].getBounds().width,420);
  assert(h.manager.list('review').find(t=>t.tabId===h.a.tabId).active);
 }finally{h.manager.dispose();}
});
test('actual presentation activation publishes one inventory and explicit select retains correlation',async()=>{
 const h=await fixture();try{
  h.manager.present(h.a,rect);h.manager.present(h.b,rect);
  assert.equal(h.inventory.length,1);assert.equal(h.inventory[0].tabs.find(t=>t.active).tabId,h.b.tabId);
  h.manager.present(h.b,{...rect,width:430});assert.equal(h.inventory.length,1);
  h.manager.select(h.a);assert.equal(h.inventory.length,2);assert.equal(h.inventory[1].tabs.find(t=>t.active).tabId,h.a.tabId);
  h.manager.select(h.a);assert.equal(h.inventory.length,3,'explicit same-tab select still emits its action-correlated inventory');
 }finally{h.manager.dispose();}
});
test('presentation deduplication cannot bypass authority, bounds, or permanent file guard refusal',async()=>{
 const h=await fixture();try{
  h.manager.present(h.a,rect);h.manager.hide();h.deny();assert.throws(()=>h.manager.present(h.a,rect));assert.equal(h.views[0].getVisible(),false);h.allow();
  assert.throws(()=>h.manager.present(h.a,{...rect,width:900}));assert.equal(h.inventory.length,0);
  h.views[0].webContents.debugger.emit('detach',{},'target closed');
  assert.throws(()=>h.manager.present(h.a,rect),error=>error.code==='GUEST_FILE_GUARD_LOST');assert.equal(h.inventory.length,0);
 }finally{h.manager.dispose();}
});
