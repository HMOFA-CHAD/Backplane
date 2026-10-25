import assert from 'node:assert/strict';
import { terminalOutputFrame, TerminalOutputPane } from '../../src/web/terminal-output.js';
import { ThinHost } from '../../src/web/thin-host.js';
import { ThinViews, VIEW_LIMITS } from '../../src/web/thin.js';

const clone = x => structuredClone(x);
const target = {kind:'thread', id:'a'}, session = {sel:'a',rid:10,drafts:{a:'unsent','@terminal.owner':'a'},open:{term:true},outbox:{},info:{}};
const link = {viewId:'v',target,greeting:{epoch:'e',generation:'3'}};
const node = (sequence, incarnation='1', pid='42') => ({type:'element',tag:'section',key:'term-pane',attrs:[{name:'class',value:'term-pane'},
  {name:'data-terminal-sequence',value:String(sequence)},{name:'data-terminal-incarnation',value:incarnation},{name:'data-terminal-pid',value:pid}],kids:[]});
const frame = (sequence=1,incarnation='1',pid='42') => ({t:'view.terminal',version:1,epoch:'e',generation:'3',viewId:'v',target:clone(target),owner:'a',sequence:String(sequence),incarnation,pid,pane:node(sequence,incarnation,pid)});
let count=0;
function check(name, f) { f();console.log('ok '+name);count++; }
check('fresh scoped frame validates',()=>assert(terminalOutputFrame(frame(),link,session)));
for (const [field,value] of [['epoch','old'],['generation','2'],['viewId','other'],['owner','b'],['sequence','281474976710656'],['sequence','0'],['incarnation','0'],['pid','4294967296'],['cmds',[]],['session',{}]]) {
  check('rejects wrong '+field+'/'+value,()=>assert.equal(terminalOutputFrame({...frame(),[field]:value},link,session),false));
}
check('rejects wrong target',()=>assert.equal(terminalOutputFrame({...frame(),target:{kind:'thread',id:'b'}},link,session),false));
check('rejects hidden popup',()=>assert.equal(terminalOutputFrame(frame(),link,{...session,open:{}}),false));
check('rejects malformed pane without throwing',()=>assert.equal(terminalOutputFrame({...frame(),pane:{...node(1),attrs:[null]}},link,session),false));
check('accepts last bounded sequence',()=>assert(terminalOutputFrame(frame(281474976710655),link,session)));

let current={...link,generation:'3',epoch:'e',owner:'a',open:true},pane,patches=[];
function full(sequence,incarnation='1',pid='42') {
  const value=node(sequence,incarnation,pid);
  pane={__v:value,parentElement:{getAttribute:k=>k==='data-terminal-owner'?'a':null},getAttribute:k=>pane.__v.attrs.find(a=>a.name===k)?.value};
}
const display=new TerminalOutputPane({document:{querySelector:()=>pane},current:()=>current,patch:(el,v)=>{patches.push(v);el.__v=v}});
full(0);display.apply();
check('push patches only current pane',()=>{assert(display.receive(node(5),frame(5)));assert.equal(pane.getAttribute('data-terminal-sequence'),'5')});
check('delayed full reply cannot roll back output',()=>{full(1);display.apply();assert.equal(pane.getAttribute('data-terminal-sequence'),'5')});
check('duplicate output does not patch again',()=>{const n=patches.length;assert(display.receive(node(5),frame(5)));assert.equal(patches.length,n)});
check('explicit close retires current popup lifetime',()=>{display.retire();assert.equal(display.receive(node(6),frame(6)),false)});
check('failed close/show can rebind same live popup only after authoritative full reply',()=>{display.rebind();assert.equal(display.receive(node(6),frame(6)),false);display.apply(true);assert(display.receive(node(6),frame(6)));display.retire()});
check('same-owner reopen accepts only new incarnation',()=>{full(6,'2');display.apply();assert.equal(display.receive(node(6),frame(6)),false);assert(display.receive(node(6,'2'),frame(6,'2')))});
check('replacement PTY needs fresh full-state process fence',()=>{assert.equal(display.receive(node(7,'2','43'),frame(7,'2','43')),false);full(7,'2','43');display.apply();assert(display.receive(node(8,'2','43'),frame(8,'2','43')));assert.equal(display.receive(node(9,'2','42'),frame(9,'2','42')),false)});
check('target change clears retained pane',()=>{current={...current,target:{kind:'thread',id:'b'}};full(9,'2','43');display.apply();assert.equal(display.receive(node(10,'2','43'),frame(10,'2','43')),false)});
check('hidden popup never resurrects',()=>{current={...current,open:false};pane=null;display.apply();assert.equal(display.receive(node(11,'2','43'),frame(11,'2','43')),false)});
check('missing visible pane requests fallback',()=>{current={...current,open:true};assert.equal(display.receive(node(12),frame(12)),false)});

function setup() {
  const sent=[],commands=[],warnings=[],settled=[],states=[];
  const h=new ThinHost({hub:'h',now:()=>0,cid:'fixture',session:()=>clone(session),target:s=>({kind:'thread',id:s.sel}),counter(){},send:r=>sent.push(r),
    prepare:s=>s,choice:(s,a,v)=>({...s,sel:a==='select'?v:s.sel}),local(){},sessionChanged(){},terminalLifetime:()=> '1',decode:x=>x,command:c=>commands.push(c),
    view(){},state:s=>states.push(s),anchor:()=>({id:'',offset:0}),ack:s=>s,blocked:()=>warnings.push('blocked'),warning:s=>warnings.push(s)},ThinViews);
  const reply=(request,input=false)=>({t:'reply',id:request.id,ok:true,result:{version:1,hub:'h',generation:'3',epoch:'e',requestRevision:request.p.requestRevision,target:clone(request.p.target),viewId:request.p.viewId||'v',viewRevision:'1',renderer:'web',remoteReady:true,session:{...clone(h.session),rid:h.session.rid+(input?1:0)},
    ...(input?{terminalInput:true,terminalOwner:'a',cmds:[{type:'send',text:JSON.stringify({id:h.session.rid+1,m:'term.input',p:{thread:'a',b:[97]}})}]}:{shown:{type:'text',text:'fixture'},window:{ids:[],older:'',hasMore:false,anchor:{id:'',offset:0},partial:[]},cmds:[]})}});
  h.greeting({t:'view',version:1,renderer:'web',generation:'3',epoch:'e',limits:VIEW_LIMITS});h.receive(reply(sent.at(-1)));
  return {h,sent,commands,warnings,settled,reply};
}
check('typing burst retains FIFO beyond ordinary seven-action limit',()=>{
  const f=setup();for(let i=0;i<64;i++)f.h.request('term-key',String.fromCharCode(65+i%26)+'\t0',ok=>f.settled.push(ok));
  assert.equal(f.h.actions.length,63);assert.equal(f.warnings.length,0);const values=[];
  for(let i=0;i<64;i++){const request=f.sent.at(-1);values.push(request.p.value);f.h.receive(f.reply(request,true))}
  assert.deepEqual(values,Array.from({length:64},(_,i)=>String.fromCharCode(65+i%26)+'\t0'));assert(f.settled.every(Boolean));assert.equal(f.commands.length,64);assert.equal(f.h.terminalBytes,0);
});
check('queued keys do not retain large chat drafts per key',()=>{
  const f=setup();f.h.request('term-key','a\t0');f.h.session.drafts.a='x'.repeat(1024*1024);
  for(let i=0;i<20;i++)f.h.request('term-key','b\t0');
  assert(f.h.actions.every(op=>JSON.stringify(op.input).length<4096));assert(f.h.terminalBytes<131072);
});
check('aggregate bytes are bounded with truthful overflow',()=>{
  const f=setup();f.h.request('term-key','a\t0');let rejected=false;f.h.request('term-paste','x'.repeat(131073),ok=>rejected=!ok);
  assert(rejected);assert(f.warnings.some(w=>w.includes('not sent')&&w.includes('full')));assert(f.h.terminalBytes<=131072);
});
check('Stop remains responsive without reordering accepted keys',()=>{
  const f=setup();for(let i=0;i<20;i++)f.h.request('term-key','a\t0');const active=f.sent.at(-1);f.h.request('stop','');f.h.receive(f.reply(active,true));assert.equal(f.sent.at(-1).p.action,'stop');
  f.h.receive(f.reply(f.sent.at(-1)));assert.equal(f.sent.at(-1).p.action,'term-key');assert.equal(f.h.actions.length,18);
});
check('Hide retires unsent scoped keys explicitly and is not blocked by burst',()=>{
  const f=setup();for(let i=0;i<20;i++)f.h.request('term-key','a\t0');const active=f.sent.at(-1);f.h.request('ws-term-hide','');
  assert.equal(f.h.terminalBytes,0);assert(f.warnings.some(w=>w.includes('cancelled')));f.h.receive(f.reply(active,true));assert.equal(f.sent.at(-1).p.action,'ws-term-hide');
});
check('disconnect retires unsent keys without replay',()=>{
  const f=setup();for(let i=0;i<20;i++)f.h.request('term-key','a\t0');f.h.disconnect();assert.equal(f.h.terminalBytes,0);assert(f.warnings.some(w=>w.includes('connection closed')));
});
console.log('terminal output focused cases: '+count);
