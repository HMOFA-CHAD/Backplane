'use strict';
// Main-process presentation only. The manager's authorize callback remains
// bound to the authenticated service authority, never a renderer's role claim.
const path = require('node:path');
const { randomUUID } = require('node:crypto');

function createBrowserSurface({electron, window, manager, authorize, onTakeover, onError=()=>{}}) {
  if(!window?.contentView||!manager||typeof authorize!=='function'||typeof onTakeover!=='function')throw new TypeError('Missing Browser surface integration');
  const shieldSession=electron.session.fromPartition('backplane-browser-shield-'+randomUUID());
  shieldSession.setPermissionRequestHandler((_wc,_permission,callback)=>callback(false));
  shieldSession.setPermissionCheckHandler(()=>false);
  const shield=new electron.WebContentsView({webPreferences:{session:shieldSession,preload:'',nodeIntegration:false,contextIsolation:true,sandbox:true,webSecurity:true,webviewTag:false,navigateOnDragDrop:false}});
  shield.setBackgroundColor('rgba(0,0,0,0)');
  shield.setVisible(false);
  const shieldURL=require('node:url').pathToFileURL(path.join(__dirname,'browser-shield.html')).href;
  shield.webContents.setWindowOpenHandler(()=>({action:'deny'}));
  shield.webContents.on('will-navigate',(event,url)=>{if(url!==shieldURL)event.preventDefault();});
  shield.webContents.on('will-attach-webview',event=>event.preventDefault());
  void shield.webContents.loadURL(shieldURL).catch(onError);
  let current=null,covered=false,disposed=false,taking=false;
  function removeShield(){
    if(!window.isDestroyed())shield.setVisible(false);
    if(covered&&!window.isDestroyed())window.contentView.removeChildView(shield);
    covered=false;
  }
  function cover(){
    if(!current||window.isDestroyed())return;
    shield.setBounds(current.bounds);
    if(!covered)window.contentView.addChildView(shield);
    shield.setVisible(true);covered=true;
  }
  function hide(){
    current=null;removeShield();
    try{manager.hide();}catch(error){onError(error);}
  }
  async function takeover(){
    if(!covered||!current||taking||disposed)return;
    taking=true;
    const target={...current.target};
    try{await onTakeover(target);}catch(error){onError(error);}finally{taking=false;}
    // An ACK is insufficient. Only a later authoritative input grant removes
    // the shield; refusal, timeout or a changed owner keeps input blocked.
    refresh();
  }
  shield.webContents.on('before-mouse-event',(event,input)=>{
    event.preventDefault();
    if(input.type==='mouseDown'&&input.button==='left')void takeover();
  });
  shield.webContents.on('before-input-event',event=>event.preventDefault());
  shield.webContents.on('context-menu',event=>event.preventDefault());
  const inputAllowed=target=>authorize({...target,operation:'direct-input'})===true;
  function refresh(){
    if(!current||disposed)return;
    const target=current.target;
    try{
      if(authorize({...target,operation:'present'})!==true)throw new Error('Browser presentation grant unavailable');
      const tab=manager.list(target.owner).find(tab=>tab.active&&tab.tabId===target.tabId&&tab.generation===target.generation);
      if(!tab)throw new Error('Stale Browser surface');
      manager.reconcileInput();
      if(inputAllowed(target)){
        const took=covered;
        removeShield();
        // The takeover click is consumed by the shield. Focus only after the
        // service grants human input, once, so later lease renewals cannot
        // steal focus from the address bar or composer.
        if(took)manager.focus(target);
      }else cover();
    }catch(error){
      // An expired or replaced lease must not leave an old interactive view.
      hide();onError(error);
    }
  }
  function present({owner,bounds}){
    if(disposed)throw new Error('Browser surface disposed');
    if(typeof owner!=='string'||!owner.length||owner.length>512||/[\x00-\x1f]/.test(owner))throw new TypeError('Invalid Browser owner');
    if(!bounds||Object.getPrototypeOf(bounds)!==Object.prototype||!['x','y','width','height'].every(key=>Number.isSafeInteger(bounds[key])))throw new TypeError('Invalid Browser bounds');
    const tabs=manager.list(owner);
    const target=tabs.find(tab=>tab.active);
    if(!target){hide();return{shown:false,reason:'No registered tab'};}
    if(current&&current.target.owner===target.owner&&current.target.tabId===target.tabId&&current.target.generation===target.generation&&['x','y','width','height'].every(key=>bounds[key]===current.bounds[key])){
      refresh();return{shown:!!current,target:current?.target,inputAllowed:!!current&&inputAllowed(target)};
    }
    const shown=manager.present(target,bounds);
    current={target:{owner:target.owner,tabId:target.tabId,generation:target.generation},bounds:{...shown.bounds}};
    if(shown.inputAllowed)removeShield();else cover();
    return{shown:true,target:current.target,inputAllowed:shown.inputAllowed};
  }
  function dispose(){
    if(disposed)return;hide();disposed=true;
    if(!shield.webContents.isDestroyed())shield.webContents.close({waitForBeforeUnload:false});
  }
  window.once('closed',dispose);
  return Object.freeze({present,hide,refresh,dispose});
}
module.exports={createBrowserSurface};
