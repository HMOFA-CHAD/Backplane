'use strict';
// Common private transport validation only. This never grants owner, target,
// recording, input or CDP permission; payload-specific handlers still must.
const {exactObject}=require('./browser-wire.cjs');
const HEX32=/^[a-f0-9]{32}$/;
const hex=value=>typeof value==='string'&&HEX32.test(value);
const LIMITS=Object.freeze({frameBytes:1048576,backlogBytes:4194304,pending:32,grantTtlMs:3000});
const OPERATIONS=new Set(['result','owner.grant','target.grant','recording.grant','grant.revoke','browser.prepare','browser.call','browser.cancel','guest.create','guest.invoke','guest.command','registry.snapshot']);
function envelope(message,lastSequence){
 exactObject(message,['v','op','id','serviceEpoch','controllerLease','payload','serverSequence']);
 if(message.v!==1||!hex(message.id)||!hex(message.serviceEpoch)||!hex(message.controllerLease)||
    !Number.isSafeInteger(lastSequence)||lastSequence<0||!Number.isSafeInteger(message.serverSequence)||message.serverSequence<=lastSequence)throw new TypeError('Invalid private Browser envelope identity');
 if(!message.payload||Object.getPrototypeOf(message.payload)!==Object.prototype)throw new TypeError('Invalid private Browser payload');
}
function identifier(value){return typeof value==='string'&&value.length>0&&value.length<=512&&!/[\x00-\x1f]/.test(value);}
function immutable(value){
 // Input is the bounded strict-JSON decoder's fresh object. Freeze iteratively
 // so authority handlers cannot mutate identity/payload after validation.
 const todo=[value],seen=new Set();
 while(todo.length){const next=todo.pop();if(!next||typeof next!=='object'||seen.has(next))continue;seen.add(next);if(seen.size>65536)throw new TypeError('Private Browser object limit');
  for(const child of Object.values(next))if(child&&typeof child==='object')todo.push(child);Object.freeze(next);
 }
 return value;
}
function validateBrowserHello(message,{requestId,expectedVersion,expectedHub=null,lastSequence=0}){
 envelope(message,lastSequence);
 if(!hex(requestId)||typeof expectedVersion!=='string'||!expectedVersion||message.op!=='hello.accept'||message.id!==requestId)throw new TypeError('Uncorrelated private Browser hello');
 const p=message.payload;exactObject(p,['protocol','version','hub','serviceEpoch','controllerLease','limits']);
 if(p.protocol!==1||p.version!==expectedVersion||!identifier(p.hub)||(expectedHub!==null&&p.hub!==expectedHub)||p.serviceEpoch!==message.serviceEpoch||p.controllerLease!==message.controllerLease)throw new TypeError('Private Browser hello does not match selected service');
 exactObject(p.limits,Object.keys(LIMITS));
 for(const [key,value]of Object.entries(LIMITS))if(p.limits[key]!==value)throw new TypeError('Unsupported private Browser limits');
 return immutable(message);
}
function validateBrowserEnvelope(message,{serviceEpoch,controllerLease,lastSequence}){
 envelope(message,lastSequence);
 if(!hex(serviceEpoch)||!hex(controllerLease)||message.serviceEpoch!==serviceEpoch||message.controllerLease!==controllerLease||!OPERATIONS.has(message.op))throw new TypeError('Stale or unsupported private Browser envelope');
 return immutable(message);
}
module.exports={validateBrowserHello,validateBrowserEnvelope,LIMITS};
