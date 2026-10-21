'use strict';

// Private main-process observations from the reviewed guest manager. This is
// document installation proof, never a service grant or renderer-facing API.
const {exactObject,targetKey}=require('./browser-wire.cjs');
const tabKey=t=>JSON.stringify([t.owner,t.tabId]);
const ref=e=>({owner:e.owner,tabId:e.tabId,generation:e.generation});
function documentIdentity(value){
 exactObject(value,['documentNonce','frameTreeNodeId','frameToken','webContentsId']);
 if(!/^[a-zA-Z0-9_-]{16,128}$/.test(value.documentNonce)||!Number.isSafeInteger(value.frameTreeNodeId)||value.frameTreeNodeId<0||
    typeof value.frameToken!=='string'||!value.frameToken||value.frameToken.length>512||!Number.isSafeInteger(value.webContentsId)||value.webContentsId<1)throw new TypeError('Invalid private guest document');
 return Object.freeze({...value});
}
function documentKey(target,doc){return JSON.stringify([targetKey(target),doc.documentNonce,doc.frameTreeNodeId,doc.frameToken,doc.webContentsId]);}

function createGuestDocuments({onRetire=()=>{}}={}){
 let serial=0;
 const tabs=new Map(),contents=new Map(),retired=new Set();
 function reset(){serial++;tabs.clear();contents.clear();retired.clear();}
 function entry(target){targetKey(target);const value=tabs.get(tabKey(target));if(!value||value.closed||value.target.generation!==target.generation)throw new Error('Stale guest document target');return value;}
 function tombstone(target,doc){
  const key=documentKey(target,doc);if(retired.has(key))return;
  if(retired.size>=8192)throw new Error('Guest document retirement limit');
  retired.add(key); // Reject queued records before notifying any callback.
  onRetire(Object.freeze({serial,target:Object.freeze({...target}),document:doc}));
 }
 function retireAll(tab){
  const old=[...tab.frames.values()];tab.frames.clear();
  for(const item of old)tombstone(tab.target,item.document);
 }
 function observe(event){
  if(!['created','generation','crashed','closed','debugger-detached','recorder-ready','recorder-document-retired','record'].includes(event.type))return null;
  const target=ref(event);targetKey(target);const key=tabKey(target);
  if(event.type==='created'){
   if(tabs.has(key)||tabs.size>=1024||typeof event.createId!=='string'||!event.createId)throw new Error('Uncorrelated or duplicate guest document registry');
   tabs.set(key,{target:Object.freeze(target),createId:event.createId,webContentsId:null,frames:new Map(),closed:false});return null;
  }
  const tab=tabs.get(key);
  if(!tab||tab.closed)throw new Error('Unknown guest document registry');
  if(['generation','crashed'].includes(event.type)){
   if(target.generation<=tab.target.generation)throw new Error('Non-advancing guest document generation');
   retireAll(tab);tab.target=Object.freeze(target);return null;
  }
  entry(target);
  if(['closed','debugger-detached'].includes(event.type)){
   retireAll(tab);tab.closed=true;if(tab.webContentsId!==null)contents.delete(tab.webContentsId);return null;
  }
  if(event.type==='recorder-ready'){
   const document=documentIdentity(event.document);
   if(typeof event.mainFrame!=='boolean')throw new TypeError('Missing private frame identity');
   const owned=contents.get(document.webContentsId);
   if((owned&&owned!==key)||(tab.webContentsId!==null&&tab.webContentsId!==document.webContentsId))throw new Error('Foreign guest WebContents proof');
   if(retired.has(documentKey(target,document)))throw new Error('Retired guest document readiness');
   const prior=tab.frames.get(document.frameTreeNodeId);
   if(prior&&documentKey(target,prior.document)!==documentKey(target,document)){
    tab.frames.delete(document.frameTreeNodeId);tombstone(target,prior.document);
   }
   if(tab.frames.size>=1024&&!tab.frames.has(document.frameTreeNodeId))throw new Error('Guest frame proof limit');
   if(event.mainFrame&&[...tab.frames.values()].some(item=>item.mainFrame&&item.document.frameTreeNodeId!==document.frameTreeNodeId))throw new Error('Conflicting guest main document');
   tab.webContentsId=document.webContentsId;contents.set(document.webContentsId,key);
   tab.frames.set(document.frameTreeNodeId,Object.freeze({document,mainFrame:event.mainFrame}));return null;
  }
  if(event.type==='recorder-document-retired'){
   const document=documentIdentity(event.document);
   if(event.mainFrame!==false||!['subframe-navigation','subframe-navigation-unresolved'].includes(event.reason)||document.webContentsId!==tab.webContentsId)throw new Error('Invalid guest frame retirement');
   const current=tab.frames.get(document.frameTreeNodeId);
   if(current?.mainFrame)throw new Error('Subframe retirement cannot remove main document');
   if(current&&documentKey(target,current.document)===documentKey(target,document))tab.frames.delete(document.frameTreeNodeId);
   tombstone(target,document);return null;
  }
  if(event.type==='record'){
   const document=documentIdentity(event.document);
   const current=tab.frames.get(document.frameTreeNodeId);
   if(!current||documentKey(target,current.document)!==documentKey(target,document)||retired.has(documentKey(target,document)))throw new Error('Unready or retired guest record');
   return Object.freeze({serial,target:Object.freeze(target),document});
  }
  return null;
 }
 function mainProof(target){
  const tab=entry(target),proof=[...tab.frames.values()].find(item=>item.mainFrame);
  if(!proof)throw new Error('Guest own main document has not acknowledged recorder');
  return proof.document;
 }
 function current(stamp){
  try{
   if(stamp.serial!==serial)return false;
   const tab=entry(stamp.target),proof=tab.frames.get(stamp.document.frameTreeNodeId);
   return !!proof&&documentKey(stamp.target,proof.document)===documentKey(stamp.target,stamp.document)&&!retired.has(documentKey(stamp.target,stamp.document));
  }catch{return false;}
 }
 return Object.freeze({observe,mainProof,current,reset});
}
module.exports={createGuestDocuments,documentIdentity};
