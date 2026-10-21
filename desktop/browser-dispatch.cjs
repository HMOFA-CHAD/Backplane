'use strict';

// Main-only dispatch lanes. Each operation keeps its original service grant;
// async CDP authorization cannot borrow another request's broader permission.
// AsyncLocalStorage.run/getStore: https://nodejs.org/api/async_context.html
const {AsyncLocalStorage}=require('node:async_hooks');
const {decodeBrowserMessage,encodeBrowserMessage,exactObject,targetKey}=require('./browser-wire.cjs');
const OPERATIONS=new Set(['cdp','select','focus','navigate','history','reload','close']);
const UNKNOWN_STATES=new WeakSet();

// Construct once for the selected service/window lifetime, then retain across
// channel, manager and dispatch replacements. There is deliberately no reset:
// ACK, new grant, socket reconnect and guest.close reply are not destruction
// proof. A future explicit native reconciliation protocol must resolve UNKNOWN.
function createBrowserUnknownState(){
 const owners=new Set();let exhausted=false;
 const state=Object.freeze({has:owner=>exhausted||owners.has(owner),latch(owner){
  if(typeof owner!=='string'||!owner.length||owner.length>512||/[\x00-\x1f]/.test(owner))throw new TypeError('Invalid UNKNOWN owner');
  if(owners.size>=4096&&!owners.has(owner)){exhausted=true;return;}
  owners.add(owner);
 }});UNKNOWN_STATES.add(state);return state;
}

function createBrowserDispatch({leases,manager,unknownState,onUnknown=()=>{}}){
 if(!leases||!manager||!UNKNOWN_STATES.has(unknownState)||typeof onUnknown!=='function')throw new TypeError('Missing private Browser dispatch integration');
 const context=new AsyncLocalStorage(),lanes=new Map(),requests=new Map();let closed=false;
 const failure=(code,dispatched)=>Object.assign(new Error(dispatched?'Browser operation outcome unknown; do not retry':'Browser operation refused before dispatch'),{code,dispatched});
 function authorize(value){
  // UNKNOWN is latched independently of later service grants. Teardown can
  // only reduce privilege; every input/record/presentation/dispatch path stays
  // denied for this owner across controller/manager replacements as well.
  if(value?.operation==='hide')return true;
  if(closed||unknownState.has(value?.owner))return false;
  return leases.authorize(value,context.getStore());
 }
 function barrier(owner){return Object.freeze([...requests.values()].filter(item=>item.target.owner===owner&&['queued','running','unknown'].includes(item.state)).map(item=>Object.freeze({id:item.id,target:item.target,state:item.state})));}
 function retireSettled(owner){
  // The controller calls this only after its authenticated outer call settles.
  // Outer transport sequence owns replay protection; these random subcommand
  // IDs must not consume lifetime slots under an unchanged permission revision.
  if([...requests.values()].some(item=>item.target.owner===owner&&['queued','running'].includes(item.state)))return false;
  for(const [id,item]of requests)if(item.target.owner===owner&&item.state==='settled')requests.delete(id);
  return true;
 }
 function close(){closed=true;for(const item of requests.values())if(item.state==='running'){item.state='unknown';unknownState.latch(item.target.owner);}}
 function unknown(item){
  item.state='unknown';unknownState.latch(item.target.owner);
  if(item.notified)return;item.notified=true;
  // This callback must synchronously revoke/hide the integrated controller.
  // Even a failed callback cannot let later operations pass this local lane.
  try{onUnknown(Object.freeze({id:item.id,target:item.target,dispatched:true}));}catch{}
 }
 function invoke(input){
  if(closed)throw failure('CONTROLLER_CLOSED',false);
  const request=decodeBrowserMessage(encodeBrowserMessage(input));
  exactObject(request,['id','target','revision','operation','params'],['method']);targetKey(request.target);
  // Completed subcommands need not consume a lifetime slot once their exact
  // authority fence is dead. Old payloads still cannot pass that stale fence.
  for(const [id,item]of requests)if(item.state==='settled'&&!item.fence.current())requests.delete(id);
  const pending=[...requests.values()].filter(item=>['queued','running'].includes(item.state)).length;
  if(!/^[a-f0-9]{32}$/.test(request.id)||requests.has(request.id)||requests.size>=1024||pending>=32)throw failure('REQUEST_LIMIT_OR_REPLAY',false);
  if(!OPERATIONS.has(request.operation)||!Number.isSafeInteger(request.revision)||request.revision<1)throw failure('INVALID_OPERATION',false);
  if(request.operation==='cdp'){
   if(typeof request.method!=='string')throw failure('INVALID_METHOD',false);
   exactObject(request.params,[],Object.keys(request.params));
  }else{
   if(request.method!==undefined)throw failure('UNEXPECTED_METHOD',false);
   exactObject(request.params,request.operation==='navigate'?['url']:request.operation==='history'?['direction']:[]);
   if(request.operation==='navigate'&&typeof request.params.url!=='string')throw failure('INVALID_URL',false);
   if(request.operation==='history'&&!['back','forward'].includes(request.params.direction))throw failure('INVALID_HISTORY_DIRECTION',false);
  }
  const authority=['history','reload'].includes(request.operation)?'navigate':request.operation;
  const fence=leases.dispatchFence(request.target,request.revision,authority,request.method??null);
  const item={id:request.id,target:Object.freeze(request.target),state:'queued',fence};requests.set(item.id,item);
  const owner=item.target.owner,prior=lanes.get(owner)??Promise.resolve();
  const result=prior.then(async()=>{
   if(closed||unknownState.has(owner)||!fence.current()){item.state='settled';throw failure('STALE_AUTHORITY',false);}
   item.state='running';
   try{
    const value=await context.run(fence,()=>{
     if(request.operation==='cdp')return manager.command(item.target,request.method,request.params);
     if(request.operation==='navigate')return manager.navigate(item.target,request.params.url);
     if(request.operation==='history')return manager.navigateHistory(item.target,request.params.direction);
     if(request.operation==='reload')return manager.reload(item.target);
     return manager[request.operation](item.target);
    });
    if(closed){unknown(item);throw failure('CONTROLLER_CLOSED_AFTER_DISPATCH',true);}
    item.state='settled';return value;
   }catch(error){
    // Only an explicit pre-dispatch refusal can prove that execution did not
    // begin. A timeout/rejected opaque operation is never reported cancelled.
    if(error?.dispatched===false){item.state='settled';throw failure('GUEST_REFUSED',false);}
    unknown(item);throw failure('GUEST_OUTCOME_UNKNOWN',true);
   }
  });
  const tail=result.catch(()=>{});lanes.set(owner,tail);void tail.then(()=>{if(lanes.get(owner)===tail)lanes.delete(owner);});
  return result;
 }
 return Object.freeze({authorize,invoke,barrier,retireSettled,close});
}
module.exports={createBrowserDispatch,createBrowserUnknownState};
