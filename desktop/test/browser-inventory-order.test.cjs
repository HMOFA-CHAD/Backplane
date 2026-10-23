'use strict';
// The actual controller uses this boundary before guest dispatch. Deferred
// inventory completion must precede native generation invalidation; grants
// still come from the real private-lease implementation.
const {test}=require('node:test'),assert=require('node:assert/strict');
const {createBrowserLeases}=require('../browser-leases.cjs');
const {settleBrowserCallRegistry}=require('../browser-controller.cjs');
function fixture(){
 let sequence=1;const leases=createBrowserLeases();leases.establish('a'.repeat(32),'b'.repeat(32));leases.receiveSequence(sequence);
 const target={owner:'review',tabId:'actual-guest',generation:4};leases.observe('created',target,{createId:'fixture'});
 const grant=revision=>leases.targetGrant({target,drive:'person',revision,ttlMs:3000,operations:['list','present','hide','navigate','direct-input'],cdpMethods:[],initializationMethods:[]});
 grant(8);
 const tab={target,ackTarget:target,revision:8},payload={owner:'review',target,grantRevision:8};
 let release,reject,entered=false;
 const pending=new Promise((resolve,fail)=>{release=resolve;reject=fail;});
 const acknowledgedRevisions=new Map([['review',8]]),state={leases,acknowledgedRevisions,drain:async owner=>{assert.equal(owner,'review');entered=true;await pending;}};
 return{leases,target,tab,payload,state,release,reject,entered:()=>entered,
  settle:()=>settleBrowserCallRegistry(state,tab,payload),
  changePolicy(){leases.revoke({scope:'mutation',owner:'review',revision:8});leases.receiveSequence(++sequence);grant(9);}};
}
test('queued inventory ACK settles under its original grant before native history advances generation',async()=>{
 const h=fixture(),order=[];
 const command=h.settle().then(()=>{
  order.push('native-dispatch');
  h.leases.observe('generation',{...h.target,generation:5});
 });
 assert.equal(h.entered(),true);assert.deepEqual(order,[]);
 // This is the inventory's unchanged original-target/current-grant ACK check.
 assert.equal(h.leases.targetGrantOf(h.target).revision,8);order.push('inventory-ack');h.release();
 await command;assert.deepEqual(order,['inventory-ack','native-dispatch']);
 assert.equal(h.leases.targetGrantOf(h.target),null);
 assert.equal(h.payload.grantRevision,8);assert.equal(h.payload.target.generation,4);
});
test('policy change while inventory is pending refuses original command before any guest operation',async()=>{
 const h=fixture();let dispatched=false;
 const command=h.settle().then(()=>{dispatched=true;});h.changePolicy();h.release();
 await assert.rejects(command,error=>error.dispatched===false);assert.equal(dispatched,false);
 assert.equal(h.leases.targetGrantOf(h.target).revision,9);assert.equal(h.payload.grantRevision,8);
});
test('unacknowledged generation or different acknowledged target cannot borrow original dispatch',async()=>{
 const h=fixture();const command=h.settle();
 h.leases.observe('generation',{...h.target,generation:5});h.tab.target={...h.target,generation:5};h.release();
 await assert.rejects(command,error=>error.dispatched===false);
 const other=fixture();const wrongAck=other.settle();other.tab.ackTarget={...other.target,tabId:'different'};other.release();
 await assert.rejects(wrongAck,error=>error.dispatched===false);
});
test('failed queued lifecycle stays failed and cannot start or retry the native command',async()=>{
 const h=fixture(),failure=new Error('inventory acknowledgement failed');let dispatched=0;
 const command=h.settle().then(()=>{dispatched++;});h.reject(failure);
 await assert.rejects(command,error=>error===failure);assert.equal(dispatched,0);
});
