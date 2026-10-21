'use strict';

// Service-issued authority only. This cache validates lifecycle and local time;
// it never decides which owner, Teach state or operation the service may grant.
const {performance}=require('node:perf_hooks');
const {exactObject,targetKey}=require('./browser-wire.cjs');
const HEX32=/^[a-f0-9]{32}$/;
const identifier=value=>typeof value==='string'&&value.length>0&&value.length<=512&&!/[\x00-\x1f]/.test(value);
const PREPARATION=new Set(['Runtime.enable','Runtime.addBinding','Runtime.removeBinding','Page.enable','Page.setInterceptFileChooserDialog','Page.addScriptToEvaluateOnNewDocument','Page.removeScriptToEvaluateOnNewDocument']);
const OPERATIONS=new Set(['list','select','present','hide','focus','navigate','close','cdp','initialize','direct-input']);
function strings(value,allowed) {
  if(!Array.isArray(value)||value.length>128||new Set(value).size!==value.length||value.some(item=>typeof item!=='string'||(allowed&&!allowed.has(item))))throw new TypeError('Invalid Browser grant operations');
  return Object.freeze([...value]);
}
const rootKey=(owner,root)=>JSON.stringify([owner,root.createId?'create': 'tab',root.createId??root.tabId]);
const tabKey=target=>JSON.stringify([target.owner,target.tabId]);

function createBrowserLeases({now=()=>performance.now(),onChange=()=>{}}={}) {
  let connection=null,serial=0,serverSequence=0;
  const grants=new Map(),revisions=new Map(),registry=new Map(),ownerFloors=new Map(),captureFloors=new Map(),usedLeases=new Set(),consumedCreates=new Set();
  function live(grant){return !!connection&&!!grant&&grant.serial===serial&&now()<grant.expires;}
  function notify(){onChange();}
  function clear(){connection=null;serial++;serverSequence=0;grants.clear();revisions.clear();registry.clear();ownerFloors.clear();captureFloors.clear();consumedCreates.clear();notify();}
  function establish(serviceEpoch,controllerLease){
    if(!HEX32.test(serviceEpoch)||!HEX32.test(controllerLease))throw new TypeError('Invalid Browser lease identity');
    const identity=serviceEpoch+':'+controllerLease;
    if(usedLeases.has(identity)||usedLeases.size>=1024)throw new Error('Repeated or exhausted Browser controller identity');
    usedLeases.add(identity);clear();connection=Object.freeze({serviceEpoch,controllerLease});notify();
  }
  function receiveSequence(sequence){
    if(!connection||!Number.isSafeInteger(sequence)||sequence<=serverSequence)throw new Error('Stale Browser service sequence');
    serverSequence=sequence;
  }
  function currentTarget(target){
    try{targetKey(target);const found=registry.get(tabKey(target));return !!connection&&!!found&&!found.retired&&found.target.generation===target.generation;}catch{return false;}
  }
  function observe(type,target,{createId=null}={}){
    targetKey(target);
    if(!connection)throw new Error('Browser controller unavailable');
    const key=tabKey(target),prior=registry.get(key);
    if(type==='created'){
      if(prior||!identifier(createId))throw new Error('Duplicate or uncorrelated Browser guest');
      if(registry.size>=1024)throw new Error('Browser registry limit');
      registry.set(key,{target:Object.freeze({...target}),createId,retired:false});
    }else{
      if(!prior||prior.retired||target.generation<prior.target.generation)throw new Error('Stale Browser lifecycle');
      if(type==='generation'||type==='crashed'){
        if(target.generation<=prior.target.generation)throw new Error('Non-advancing Browser generation');
        grants.delete('target:'+targetKey(prior.target));
        prior.target=Object.freeze({...target});
        // A crash cannot inherit prospective capture, even if its tab survives.
        if(type==='crashed')retireCapture(prior);
      }else if(type==='closed'||type==='debugger-detached'){
        grants.delete('target:'+targetKey(prior.target));retireCapture(prior);prior.retired=true;
      }else throw new TypeError('Invalid Browser lifecycle');
    }
    notify();
  }
  function retireCapture(entry){
    grants.delete('record:'+rootKey(entry.target.owner,{tabId:entry.target.tabId}));
    grants.delete('record:'+rootKey(entry.target.owner,{createId:entry.createId}));
  }
  function accept(key,payload,body){
    if(!connection)throw new Error('Browser controller unavailable');
    if(!Number.isSafeInteger(payload.revision)||payload.revision<1||!Number.isSafeInteger(payload.ttlMs)||payload.ttlMs<1||payload.ttlMs>3000)throw new TypeError('Invalid Browser grant lifetime');
    const owner=body.owner??body.target.owner;
    const previous=grants.get(key),priorRevision=revisions.get(key)??0;
    const floor=key.startsWith('record:')?captureFloors:ownerFloors;
    if(serverSequence<1||payload.revision<priorRevision||payload.revision<=(floor.get(owner)??0))throw new Error('Stale Browser grant revision');
    if(payload.revision===priorRevision){
      // Revision is authority, not a heartbeat counter. Renew only an existing
      // live identical permission; a newer frame cannot revive expired/revoked
      // authority or broaden an old in-flight command's allowed methods.
      if(!live(previous)||serverSequence<=previous.serverSequence||JSON.stringify(previous.body)!==JSON.stringify(body))throw new Error('Invalid Browser grant renewal');
    }
    if(!revisions.has(key)&&revisions.size>=4096)throw new Error('Browser grant limit');
    revisions.set(key,payload.revision);
    const value=Object.freeze({...body,body,revision:payload.revision,serial,serverSequence,expires:now()+payload.ttlMs});
    grants.set(key,value);notify();return value;
  }
  function ownerGrant(payload){
    exactObject(payload,['owner','revision','ttlMs','operations'],['createId']);
    if(!identifier(payload.owner)||(payload.createId!==undefined&&!identifier(payload.createId)))throw new TypeError('Invalid Browser owner grant');
    const operations=strings(payload.operations,new Set(['create','list']));
    if(operations.includes('create')&&!payload.createId)throw new TypeError('Missing Browser create correlation');
    return accept('owner:'+payload.owner,payload,{owner:payload.owner,operations,createId:payload.createId??null});
  }
  function targetGrant(payload){
    exactObject(payload,['target','revision','ttlMs','operations','cdpMethods','initializationMethods','drive']);
    if(!currentTarget(payload.target))throw new Error('Unregistered Browser target');
    const operations=strings(payload.operations,OPERATIONS),cdpMethods=strings(payload.cdpMethods),initializationMethods=strings(payload.initializationMethods,PREPARATION);
    if(!['none','agent','person'].includes(payload.drive)||cdpMethods.some(method=>!/^\w+\.\w+$/.test(method)))throw new TypeError('Invalid Browser target grant');
    if((payload.drive!=='person'&&(operations.includes('direct-input')||operations.includes('focus')))||
       (payload.drive!=='agent'&&(operations.includes('cdp')||cdpMethods.length)))throw new TypeError('Conflicting Browser drive grant');
    return accept('target:'+targetKey(payload.target),payload,{target:Object.freeze({...payload.target}),operations,cdpMethods,initializationMethods,drive:payload.drive});
  }
  function recordingGrant(payload){
    exactObject(payload,['owner','revision','ttlMs','root','documents','popupDescendants','enabled']);
    if(!identifier(payload.owner)||payload.popupDescendants!==false||payload.documents!=='prospective'||typeof payload.enabled!=='boolean')throw new TypeError('Invalid Browser recording scope');
    const root=payload.root;
    if(root?.createId!==undefined){
      exactObject(root,['createId']);
      const owner=grants.get('owner:'+payload.owner);
      const registered=[...registry.values()].some(entry=>!entry.retired&&entry.target.owner===payload.owner&&entry.createId===root.createId);
      if(!identifier(root.createId)||(!registered&&(!live(owner)||owner.createId!==root.createId)))throw new Error('Unregistered Browser create recording root');
    }else{
      exactObject(root,['tabId']);
      const entry=registry.get(tabKey({owner:payload.owner,tabId:root.tabId}));
      if(!identifier(root.tabId)||!entry||entry.retired)throw new Error('Unregistered Browser recording root');
    }
    const grant=accept('record:'+rootKey(payload.owner,root),payload,{owner:payload.owner,root:Object.freeze({...root}),enabled:payload.enabled});
    if(root.tabId){
      const entry=registry.get(tabKey({owner:payload.owner,tabId:root.tabId}));
      // Once service registration replaces a pending create root, its older
      // capture grant must not survive a disabled exact-tab grant.
      grants.delete('record:'+rootKey(payload.owner,{createId:entry.createId}));
    }
    return grant;
  }
  function canOwner(owner,operation,createId){
    const value=grants.get('owner:'+owner);
    return live(value)&&value.operations.includes(operation)&&(operation!=='create'||(value.createId===createId&&!consumedCreates.has(JSON.stringify([owner,createId]))));
  }
  function consumeCreate(owner,createId){
    if(!canOwner(owner,'create',createId))throw new Error('Browser create refused');
    if(consumedCreates.size>=1024)throw new Error('Browser create correlation limit');
    consumedCreates.add(JSON.stringify([owner,createId]));
  }
  function canTarget(target,operation){
    if(!currentTarget(target))return false;
    const value=grants.get('target:'+targetKey(target));
    return live(value)&&value.operations.includes(operation);
  }
  function captureGrant(context,requireEnabled=true){
    if(context.opener||!currentTarget({owner:context.owner,tabId:context.tabId,generation:context.generation}))return null;
    const entry=registry.get(tabKey(context));
    const byTab=grants.get('record:'+rootKey(context.owner,{tabId:context.tabId}));
    const byCreate=grants.get('record:'+rootKey(context.owner,{createId:entry.createId}));
    const grant=live(byTab)?byTab:live(byCreate)?byCreate:null;
    return grant&&(!requireEnabled||grant.enabled)?grant:null;
  }
  function captureStamp(context){
    const grant=captureGrant(context),document=context.document;
    if(!grant)return null;
    exactObject(document,['documentNonce','frameTreeNodeId','frameToken','webContentsId']);
    if(!/^[a-zA-Z0-9_-]{16,128}$/.test(document.documentNonce)||!Number.isSafeInteger(document.frameTreeNodeId)||!identifier(document.frameToken)||!Number.isSafeInteger(document.webContentsId))return null;
    return Object.freeze({...connection,grantRevision:grant.revision,target:Object.freeze({owner:context.owner,tabId:context.tabId,generation:context.generation}),document:Object.freeze({...document})});
  }
  function captureCurrent(stamp){
    try{
      const current=captureStamp({...stamp.target,document:stamp.document});
      return !!current&&current.serviceEpoch===stamp.serviceEpoch&&current.controllerLease===stamp.controllerLease&&current.grantRevision===stamp.grantRevision;
    }catch{return false;}
  }
  function dispatchFence(target,revision,operation,method=null){
    targetKey(target);
    const born=serial,key='target:'+targetKey(target),ref=Object.freeze({...target});
    const matches=()=>{
      const grant=grants.get(key);
      return born===serial&&currentTarget(ref)&&live(grant)&&grant.revision===revision&&grant.operations.includes(operation)&&
        (method===null||grant.cdpMethods.includes(method));
    };
    if(!matches())throw new Error('Browser dispatch refused');
    return Object.freeze({target:ref,revision,operation,method,current:matches});
  }
  function ownerFence(owner,revision,operation,createId=null){
    if(!['list','create'].includes(operation))throw new TypeError('Invalid owner operation');
    const born=serial;
    const current=()=>born===serial&&grants.get('owner:'+owner)?.revision===revision&&canOwner(owner,operation,createId);
    if(!current())throw new Error('Browser owner authority unavailable');
    return Object.freeze({owner,revision,operation,createId,current});
  }
  function targetGrantOf(target){
    if(!currentTarget(target))return null;
    const grant=grants.get('target:'+targetKey(target));
    return live(grant)?grant:null;
  }
  function authorize(context,dispatch=null){
    try{
      if(!connection)return false;
      const {operation,owner,tabId,generation}=context;
      if(operation==='create'||(operation==='list'&&tabId===null))return canOwner(owner,operation,context.createId);
      const target={owner,tabId,generation};
      if(operation==='list')return canOwner(owner,'list')&&currentTarget(target);
      if(operation==='recording')return !!captureGrant(context,false);
      if(operation==='record-event')return !!captureStamp(context);
      if(operation==='cdp'){
        if(context.initialization){
          const grant=grants.get('target:'+targetKey(target));
          return PREPARATION.has(context.method)&&canTarget(target,'initialize')&&grant.initializationMethods.includes(context.method);
        }
        return !!dispatch&&dispatch.operation==='cdp'&&dispatch.method===context.method&&targetKey(dispatch.target)===targetKey(target)&&dispatch.current();
      }
      // Hiding can only reduce authority; it must work after expiry/retirement.
      if(operation==='hide')return true;
      if(dispatch&&['navigate','select','focus','close'].includes(operation))return dispatch.operation===operation&&targetKey(dispatch.target)===targetKey(target)&&dispatch.current();
      return canTarget(target,operation);
    }catch{return false;}
  }
  function revoke(payload){
    const {scope,owner,revision,captureRevision}=payload;
    if(!['mutation','all'].includes(scope))throw new TypeError('Explicit Browser revocation scope required');
    exactObject(payload,scope==='all'?['scope','owner','revision','captureRevision']:['scope','owner','revision']);
    if(!identifier(owner)||!Number.isSafeInteger(revision)||revision<1)throw new TypeError('Invalid Browser revocation');
    if(scope==='all'&&(!Number.isSafeInteger(captureRevision)||captureRevision<0))throw new TypeError('Invalid Browser capture floor');
    if(revision<(ownerFloors.get(owner)??0))throw new Error('Stale Browser revocation');
    if(scope==='all'&&captureRevision<(captureFloors.get(owner)??0))throw new Error('Stale Browser capture revocation');
    for(const [key,grant]of grants){
      const grantOwner=grant.owner??grant.target?.owner;
      if(grantOwner!==owner)continue;
      if(key.startsWith('record:')){if(scope==='all'&&captureRevision<grant.revision)throw new Error('Stale Browser capture revocation');}
      else if(revision<grant.revision)throw new Error('Stale Browser revocation');
    }
    if(!ownerFloors.has(owner)&&ownerFloors.size>=4096)throw new Error('Browser revocation limit');
    ownerFloors.set(owner,revision);
    if(scope==='all')captureFloors.set(owner,captureRevision);
    for(const [key,grant]of [...grants]){
      const grantOwner=grant.owner??grant.target?.owner;
      if(grantOwner!==owner)continue;
      const capture=key.startsWith('record:');if(capture&&scope==='mutation')continue;
      grants.delete(key);revisions.set(key,Math.max(revisions.get(key)??0,capture?captureRevision:revision));
    }
    notify();
  }
  function expire(){
    let changed=false;
    for(const [key,value]of grants)if(!live(value)){grants.delete(key);changed=true;}
    if(changed)notify();
  }
  function deadline(){return Math.min(Infinity,...[...grants.values()].map(grant=>grant.expires));}
  return Object.freeze({establish,clear,receiveSequence,observe,ownerGrant,targetGrant,recordingGrant,consumeCreate,authorize,dispatchFence,ownerFence,targetGrantOf,captureStamp,captureCurrent,revoke,expire,deadline,currentTarget});
}
module.exports={createBrowserLeases};
