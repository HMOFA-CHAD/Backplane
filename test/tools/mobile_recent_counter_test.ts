import assert from 'node:assert/strict';
const before=process.argv.includes('--before');
const {Recent}=before ? await import('../fixtures/mobile_recent_before_nat.mjs') : await import('../../src/mobile/recent.js');
const MAX=2**48-1;
let checks=0;const ok=(name:string,f:()=>void)=>{f();checks++;console.log('ok '+name);};
const sessions=new Map<string,any>();const emitted:any[]=[];const performed:any[]=[];
const api={prepare:(s:any)=>s,now:()=>0,cid:()=>'fixture',session:(k:string)=>structuredClone(sessions.get(k)),send:(key:string,wire:any)=>{const c={key,wire};emitted.push(c);return c;},command:(c:any)=>{performed.push(c);return c;},adopt:()=>{throw Error('unexpected adopt during counter recovery');}};
function fixture(rid:any){return {rid,sel:'current',drafts:{current:'newer 日本語'},outbox:{'previous-id':'original request bytes'},origin:'canonical-origin',seq:12025};}
if(before){
 sessions.set('A',fixture(0));const c:any=new Recent(api).open('A','epoch-old')[0];
 assert.ok(Number.isSafeInteger(c.wire.p.session.rid)&&c.wire.p.session.rid<MAX,'FAIL old current-epoch seed exceeds native Nat bound');
 throw Error('old semantic red unexpectedly passed');
}
const r:any=new Recent(api);sessions.set('valid',fixture(0));
ok('current epoch milliseconds fit safeinteger and Native Nat',()=>{const c:any=r.open('valid','current-gen')[0];assert.equal(c.wire.m,'mobile.screen');assert.ok(Number.isSafeInteger(c.wire.p.session.rid));assert.ok(c.wire.p.session.rid<MAX);r.close('valid');});
sessions.set('near',fixture(MAX-1));
ok('valid near-limit retained ID never decreases or wraps',()=>{const c:any=r.open('near','near-gen')[0];assert.equal(c.wire.p.session.rid,MAX-1);assert.equal(c.wire.m,'mobile.screen');r.close('near');});
for(const [name,value] of [['Natmax',MAX],['NatOverflow',MAX+1],['UnsafeInteger',Number.MAX_SAFE_INTEGER+1],['negative',-1],['fractional',.5],['NaN',NaN],['infinite',Infinity],['string','123'],['null',null]] as const){
 const state=fixture(value);sessions.set(name,state);const frozen=structuredClone(state);const prior=emitted.length;const cmds:any[]=r.open(name,'generation-'+name);
 ok(name+' recovers through exact-generation history only',()=>{assert.equal(cmds.length,1);assert.equal(cmds[0].wire.m,'mobile.history');assert.deepEqual(cmds[0].wire.p,{generation:'generation-'+name});assert.equal(r.active(name),false);});
 ok(name+' does not mutate draft outbox cursor or epoch',()=>assert.deepEqual(sessions.get(name),frozen));
 ok(name+' does not dispatch ordinary action or reuse ID',()=>{assert.equal(emitted.length,prior+1);assert.ok(Number.isSafeInteger(cmds[0].wire.id)&&cmds[0].wire.id<MAX);assert.equal(new Set(emitted.map(x=>x.wire.id)).size,emitted.length);assert.equal(performed.length,0);});
 ok(name+' cannot accept late presentation success',()=>assert.equal(r.reply(name,{id:cmds[0].wire.id,ok:true,result:{mobile:1,session:fixture(1),cmds:[{type:'send',text:'late'}]}}),null));
}
const old=Date.now;
try{Date.now=()=>NaN;sessions.set('wall',fixture(0));ok('invalid wall clock falls back without seed coercion',()=>assert.equal(r.open('wall','wall-gen')[0].wire.m,'mobile.history'));}finally{Date.now=old;}
ok('recovering one hub never changes another hub',()=>assert.deepEqual(sessions.get('valid'),fixture(0)));
console.log('PASS bounded current Recent counters/fallback '+checks+' checks; pure model only');
