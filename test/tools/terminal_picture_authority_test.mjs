import assert from 'node:assert/strict';
import { ThinViews, VIEW_LIMITS, VIEW_ID_BASE } from '../../src/web/thin.js';
import { ThinHost } from '../../src/web/thin-host.js';
const copy=x=>structuredClone(x), target={kind:'thread',id:'a'};
const session={sel:'a',rid:10,drafts:{a:'unsent','@terminal.owner':'a'},open:{term:true},info:{},outbox:{}};
let count=0;
function check(name,fn){fn();console.log('ok '+name);count++;}
function setup(renderer='web'){
 const sent=[],client=new ThinViews({now:()=>0,send:(_,r)=>{sent.push(r);return r},command:(command,input)=>({command,input}),validateResult:r=>r.rejectFixture!==true},VIEW_ID_BASE+1);
 const greeting={t:'view',version:1,renderer,generation:'3',epoch:'e',limits:VIEW_LIMITS};client.connect('h',greeting);
 function reply(request,{compact=false,revision='15',extra={}}={}){
  return {t:'reply',id:request.id,ok:true,result:{version:1,hub:'h',generation:'3',epoch:'e',requestRevision:request.p.requestRevision,target:copy(request.p.target),viewId:request.p.viewId||'v',viewRevision:revision,renderer,remoteReady:true,session:copy(session),cmds:[],
   ...(compact?{terminalInput:true,terminalOwner:'a'}:{shown:{type:'text',text:'canonical '+revision},window:{ids:[],older:'',hasMore:false,anchor:{id:'',offset:0},partial:[]}}),...extra}};
 }
 client.select('h',target,copy(session),'fixture');client.reply('h',reply(sent.at(-1),{revision:'14'}));
 const link=client.links.get('h');
 const changed=revision=>client.changed('h',{t:'view.changed',version:1,generation:'3',epoch:'e',viewId:'v',target,viewRevision:revision},copy(session),{id:'',offset:0});
 const input=(extra={})=>{client.request('h','view.action',{session:copy(session),action:'term-key',value:'a\t0',terminalInput:true,terminalOwner:'a',...extra});return sent.at(-1)};
 const read=()=>{changed('15');return sent.at(-1)};
 const action=(action='flag')=>{client.request('h','view.action',{session:copy(session),action,value:'models'});return sent.at(-1)};
 return {client,link,sent,reply,changed,input,read,action};
}
check('one canonical refresh converges across successive compact input replies',()=>{
 const f=setup(),read=f.read();
 for(let i=0;i<4;i++){const key=f.input();const ack=f.client.reply('h',f.reply(key,{compact:true}));assert(ack.current&&ack.inputOnly);assert.equal(f.link.changedRevision,'15')}
 assert(f.link.revision>read.p.requestRevision);const full=f.client.reply('h',f.reply(read));
 assert(full.current&&full.remoteReady);assert.equal(f.link.viewRevision,'15');assert.equal(f.link.invalidated,false);assert.equal(full.refreshDue,false);assert.equal(f.sent.filter(r=>r.m==='view.update').length,1);
});
check('compact ACK never covers a real canonical invalidation',()=>{
 const f=setup(),read=f.read(),key=f.input();f.client.reply('h',f.reply(key,{compact:true}));
 assert.equal(f.link.viewRevision,'14');assert.equal(f.link.changedRevision,'15');assert(f.link.updatePending);assert.notEqual(read.id,key.id);
});
check('a newer canonical change remains pending after the earlier full read',()=>{
 const f=setup(),read=f.read(),key=f.input();f.client.reply('h',f.reply(key,{compact:true}));f.changed('16');
 const full=f.client.reply('h',f.reply(read));assert(full.current&&full.refreshDue);assert.equal(f.link.changedRevision,'16');assert(f.link.invalidated);
});
check('an explicit queued read is not consumed by canonical revision coverage',()=>{
 const f=setup(),read=f.read();f.client.request('h','view.update',{session:copy(session)});const key=f.input();f.client.reply('h',f.reply(key,{compact:true}));
 const full=f.client.reply('h',f.reply(read));assert(full.current&&full.refreshDue);assert(f.link.readInvalidated&&f.link.invalidated);
});
check('a genuine navigation action still retires the old picture',()=>{
 const f=setup(),read=f.read();f.action();assert.equal(f.client.reply('h',f.reply(read)).current,false);
});
check('selection and owner changes cannot borrow the previous picture',()=>{
 const f=setup(),read=f.read();f.client.select('h',{kind:'thread',id:'b'},{...copy(session),sel:'b'},'fixture');assert.equal(f.client.reply('h',f.reply(read)).current,false);assert.equal(f.link.terminalOwner,'');
});
for(const [name,args] of [['wrong owner',{terminalOwner:'b'}],['hidden input',{session:{...copy(session),open:{}}}],['generic terminal flag',{action:'flag'}],['model menu',{action:'flag',value:'models',modelMenuInput:true}]])check(name+' keeps ordinary supersession',()=>{
 const f=setup(),read=f.read(),key=f.input(args);assert.equal(f.client.calls.get(key.id).terminalInputIntent,false);assert.equal(f.client.reply('h',f.reply(read)).current,false);
});
check('native input keeps ordinary supersession',()=>{const f=setup('mobile'),read=f.read(),key=f.input();assert.equal(f.client.calls.get(key.id).terminalInputIntent,false);assert.equal(f.client.reply('h',f.reply(read)).current,false)});
check('a validated terminal full fallback becomes a picture barrier',()=>{
 const f=setup(),read=f.read(),key=f.input();const full=f.client.reply('h',f.reply(key));assert(full.current&&!full.inputOnly);assert.equal(f.link.pictureRevision,key.p.requestRevision);assert.equal(f.client.reply('h',f.reply(read)).current,false);
});
check('an older full fallback cannot overtake a newer real action',()=>{
 const f=setup();f.read();const key=f.input(),navigation=f.action();assert.equal(f.client.reply('h',f.reply(key)).current,false);assert.equal(f.link.pictureRevision,navigation.p.requestRevision);
});
check('a malformed compact reply grants no picture authority',()=>{
 const f=setup(),read=f.read(),key=f.input();const barrier=f.link.pictureRevision;assert(f.client.reply('h',f.reply(key,{compact:true,extra:{shown:{type:'text',text:'invalid'}}})).failed);assert.equal(f.link.pictureRevision,barrier);assert(f.client.reply('h',f.reply(read)).current);
});
check('invalid presentation and failed input do not promote a fallback',()=>{
 const f=setup(),read=f.read(),key=f.input();const barrier=f.link.pictureRevision;assert(f.client.reply('h',f.reply(key,{extra:{rejectFixture:true}})).failed);assert.equal(f.link.pictureRevision,barrier);
 const next=f.input();assert(f.client.reply('h',{t:'reply',id:next.id,ok:false,error:{code:'fixture'}}).failed);assert.equal(f.link.pictureRevision,barrier);assert(f.client.reply('h',f.reply(read)).current);
});
check('wire-stale picture-current read errors remain actionable in the host',()=>{
 const f=setup(),read=f.read();f.input();assert(ThinHost.prototype.isCurrent.call({client:f.client,hub:'h'},{wireRevision:read.p.requestRevision,target,pictureAuthority:true}));
 assert.equal(ThinHost.prototype.isCurrent.call({client:f.client,hub:'h'},{wireRevision:read.p.requestRevision,target,pictureAuthority:false}),false);
});
check('disconnect discards old read and input authority',()=>{const f=setup(),read=f.read(),key=f.input();f.client.disconnect('h');assert.equal(f.client.reply('h',f.reply(read)),null);assert.equal(f.client.reply('h',f.reply(key,{compact:true})),null)});
console.log('terminal picture authority focused cases: '+count);
