'use strict';
// Exercise authenticated policy leases against the controller's actual idle
// lifecycle handoff. Native same-guest proof remains the integrator's suffix.
const {test}=require('node:test'),assert=require('node:assert/strict');
const {createBrowserLeases}=require('../browser-leases.cjs');
const {adoptIdleBrowserGrant}=require('../browser-controller.cjs');
const key=t=>JSON.stringify([t.owner,t.tabId]);
function fixture(){
 let now=0,sequence=1;
 const leases=createBrowserLeases({now:()=>now});leases.establish('a'.repeat(32),'b'.repeat(32));leases.receiveSequence(sequence);
 const target={owner:'review',tabId:'actual-guest',generation:1};leases.observe('created',target,{createId:'fixture'});
 const tab={target,ackTarget:target,offered:true,creationCompleted:true,prep:null,activeCall:null,revision:3};
 const tabs=new Map([[key(target),tab]]),preparing=new Map(),acknowledgedRevisions=new Map([[target.owner,3]]);
 const context={leases,tabs,preparing,acknowledgedRevisions};
 function grant(drive,revision){
  leases.ownerGrant({owner:target.owner,revision,ttlMs:3000,operations:['list']});
  leases.targetGrant({target,drive,revision,ttlMs:3000,operations:drive==='agent'?['list','present','hide','cdp']:['list','present','hide','focus','direct-input','navigate'],cdpMethods:drive==='agent'?['Input.dispatchMouseEvent']:[],initializationMethods:[]});
 }
 grant('agent',3);
 return{...context,target,tab,grant,adopt:()=>adoptIdleBrowserGrant(context,target),expire:()=>{now=3000;},
  policy(drive,revision){leases.revoke({scope:'mutation',owner:target.owner,revision:revision-1});leases.receiveSequence(++sequence);grant(drive,revision);}};
}
test('takeover and handback advance idle registry authority without replacing the guest or old dispatch fence',()=>{
 const h=fixture(),guest=h.tab,original=h.leases.dispatchFence(h.target,3,'cdp','Input.dispatchMouseEvent');
 h.policy('person',4);assert.equal(original.current(),false);assert.equal(original.revision,3);
 assert.equal(h.adopt(),true);assert.equal(h.acknowledgedRevisions.get('review'),4);assert.equal(h.tab.revision,4);assert.equal(h.tabs.get(key(h.target)),guest);
 assert.equal(h.leases.authorize({...h.target,operation:'direct-input'}),true);
 assert.throws(()=>h.leases.dispatchFence(h.target,3,'cdp','Input.dispatchMouseEvent'));
 h.policy('agent',5);assert.equal(h.adopt(),true);assert.equal(h.acknowledgedRevisions.get('review'),5);assert.equal(h.tab.revision,5);assert.equal(h.tabs.get(key(h.target)),guest);
 assert.equal(h.leases.authorize({...h.target,operation:'direct-input'}),false);assert.equal(original.current(),false);
 assert.equal(h.leases.dispatchFence(h.target,5,'cdp','Input.dispatchMouseEvent').current(),true);
});
test('another tab cannot rebase an owner command or an unacknowledged navigation/preparation',()=>{
 const h=fixture();h.policy('person',4);
 const other={target:{...h.target,tabId:'other'},activeCall:{id:'original-command',revision:3}};h.tabs.set(key(other.target),other);
 assert.equal(h.adopt(),false);assert.equal(h.acknowledgedRevisions.get('review'),3);assert.equal(other.activeCall.revision,3);
 other.activeCall=null;h.tab.ackTarget={...h.target,generation:0};assert.equal(h.adopt(),false);
 h.tab.ackTarget=h.target;h.preparing.set('review',{});assert.equal(h.adopt(),false);h.preparing.clear();
 h.tab.prep={};assert.equal(h.adopt(),false);h.tab.prep=null;h.tab.creationCompleted=false;assert.equal(h.adopt(),false);
 assert.equal(h.tab.revision,3);assert.equal(h.acknowledgedRevisions.get('review'),3);
});
test('expired or disconnected policy cannot revive idle lifecycle authority',()=>{
 const h=fixture();h.policy('person',4);h.expire();assert.equal(h.adopt(),false);assert.equal(h.tab.revision,3);
 h.leases.clear();assert.equal(h.adopt(),false);assert.equal(h.acknowledgedRevisions.get('review'),3);
});
