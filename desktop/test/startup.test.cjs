'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
async function fixture(rid=1){
 const {FrontendStartup}=await import('../../src/web/startup.js');
 let session={sel:'A',drafts:{A:'original'},rid},cursor={since:0,origin:''},at=0,next=0;
 const timers=new Map(),sent=[],views=[],commands=[],performed=[],fallbacks=[],adoptions=[];
 const choice=(s,action,value)=>action==='select'?{...s,sel:value}:action==='draft'?{...s,drafts:{...s.drafts,[s.sel]:value}}:s;
 const api={session:()=>session,cursor:()=>({...cursor}),cid:()=> 'fixture',send:o=>sent.push(o),allowed:a=>['select','draft','send','fold'].includes(a),blocked:a=>commands.push({blocked:a}),choice,
  prepare:s=>s,local(){},decode:r=>{if(!r.view||r.view.invalid)throw Error('invalid view');return r.view;},view:n=>views.push(n),hide(){},
  command:c=>commands.push(c),ack:(s,e)=>({...s,ack:e.id}),adopt:s=>{session=s;adoptions.push(s);},perform:o=>performed.push(o),legacy:(why,pending)=>fallbacks.push({why,pending})};
 const startup=new FrontendStartup(api,{setTimer:(fn,ms)=>{const id=++next;timers.set(id,{fn,at:at+ms});return id;},clearTimer:id=>timers.delete(id)});
 const tick=ms=>{at+=ms;for(const [id,t]of [...timers])if(t.at<=at&&timers.has(id)){timers.delete(id);t.fn();}};
 const greet=()=>startup.greeting({protocol:1,generation:'7'});
 const reply=(request=sent.find(x=>x.m==='frontend.screen'),extra={})=>({id:request.id,ok:true,result:{frontend:1,web:1,session:{sel:'A',drafts:{A:'old response'},rid:3},view:{text:'early'},cmds:[],revision:request.p.revision,...extra}});
 return{startup,sent,views,commands,performed,fallbacks,adoptions,tick,greet,reply,setCursor:c=>cursor=c};
}
test('history starts after actual cache completion without any screen reply',async()=>{
 const f=await fixture();f.startup.opened();f.greet();assert(!f.sent.some(x=>x.m==='frontend.history'));
 f.setCursor({since:123,origin:'actual'});f.startup.ready();assert.deepEqual(f.sent.find(x=>x.m==='frontend.history').p,{generation:'7',since:123,origin:'actual'});f.startup.ready();assert.equal(f.sent.filter(x=>x.m==='frontend.history').length,1);
});
test('missing greeting falls back boundedly and never fabricates a cursor',async()=>{
 const f=await fixture();f.startup.opened();f.tick(2000);assert.equal(f.fallbacks.length,1);assert.equal(f.sent.length,0);f.startup.ready();assert.equal(f.sent.length,0);
});
test('invalid greeting falls back without accepting its identity',async()=>{
 const f=await fixture();f.startup.greeting({protocol:2,generation:'forged'});assert.equal(f.fallbacks.length,1);assert.equal(f.sent.length,0);
});
test('invalid screen decode cannot block history or issue its commands',async()=>{
 const f=await fixture();f.greet();f.startup.reply(f.reply(undefined,{view:{invalid:true},cmds:[{type:'send',text:'bad'}]}));f.startup.ready();assert(f.sent.some(x=>x.m==='frontend.history'));assert.equal(f.commands.length,0);assert.equal(f.views.length,0);
});
test('missing screen times out while history continues',async()=>{
 const f=await fixture();f.greet();f.startup.ready();f.startup.canonicalFrame();f.tick(2000);assert.equal(f.startup.phase,'history');assert.equal(f.fallbacks.length,0);
});
test('missing canonical history switches to legacy once',async()=>{
 const f=await fixture();f.greet();f.startup.ready();f.tick(5000);assert.equal(f.fallbacks.length,1);f.tick(5000);assert.equal(f.fallbacks.length,1);
});
test('old hub canonical data suppresses the unsupported greeting fallback',async()=>{
 const f=await fixture();f.startup.opened();f.startup.canonicalFrame();f.startup.ready();f.tick(8000);assert.equal(f.fallbacks.length,0);assert.equal(f.sent.length,0);
});
test('late or duplicate presentation after canonical cannot render adopt or issue',async()=>{
 const f=await fixture();f.greet();const reply=f.reply(undefined,{cmds:[{type:'send',text:'one'}]});f.startup.ready();f.startup.canonicalFrame();f.startup.end();const before=f.adoptions.length;
 assert(f.startup.reply(reply));assert(f.startup.reply(reply));assert.equal(f.commands.length,0);assert.equal(f.views.length,0);assert.equal(f.adoptions.length,before);
});
test('new selection overtakes a traveling refresh and its late view is retired',async()=>{
 const f=await fixture();f.greet();const old=f.reply();f.startup.request('select','B');assert(f.startup.reply(old));assert.equal(f.views.length,0);assert.equal(f.startup.session.sel,'B');
});
test('new draft overtakes a valid old action view without dropping its command',async()=>{
 const f=await fixture();f.greet();f.startup.request('send','');const active=f.sent.filter(x=>x.m==='frontend.screen').at(-1);f.startup.request('draft','new 日本語');const reply=f.reply(active,{cmds:[{type:'send',text:'captured original'}]});
 f.startup.reply(reply);f.startup.reply(reply);assert.equal(f.views.length,0);assert.equal(f.commands.length,1);assert.equal(f.startup.session.drafts.A,'new 日本語');
});
test('new selection and its draft both survive an older matching action result',async()=>{
 const f=await fixture();f.greet();f.startup.request('send','');const active=f.sent.filter(x=>x.m==='frontend.screen').at(-1);f.startup.request('select','B');f.startup.request('draft','B draft');f.startup.reply(f.reply(active));
 assert.equal(f.startup.session.sel,'B');assert.equal(f.startup.session.drafts.B,'B draft');assert.equal(f.views.length,0);
});
test('canonical-only actions are refused now rather than queued for handoff',async()=>{
 const f=await fixture();f.greet();f.startup.request('br-go','private');f.startup.request('mail-send','private');f.startup.end();assert.equal(f.performed.length,0);assert.equal(f.commands.filter(c=>c.blocked).length,2);
});
test('unanswered pure action transfers once and ignores its late reply',async()=>{
 const f=await fixture();f.greet();f.startup.request('send','');const old=f.reply(f.sent.filter(x=>x.m==='frontend.screen').at(-1));f.startup.end();f.startup.end();f.startup.reply(old);assert.equal(f.performed.length,1);assert.equal(f.commands.length,0);
});
test('ordinary id namespace remains inside Bend immediate Nat range',async()=>{
 const f=await fixture();assert(f.startup.session.rid>1);assert(f.startup.session.rid<2**48);
});
test('an invalid later command prevents every command in the response from issuing',async()=>{
 const {validatePresentation}=await import('../../src/web/startup.js');const f=await fixture();f.startup.api.decode=r=>{validatePresentation(r);return r.view;};
 f.greet();f.startup.request('send','');const request=f.sent.filter(x=>x.m==='frontend.screen').at(-1);
 f.startup.reply(f.reply(request,{view:{type:'text',text:'safe'},cmds:[{type:'send',text:JSON.stringify({id:1,m:'message.send',p:{}})},{type:'unknown'}]}));
 assert.equal(f.commands.length,0);f.startup.end();assert.equal(f.performed.length,1);
});
test('a local command failure after dispatch never makes the operation eligible for replay',async()=>{
 const f=await fixture();f.greet();f.startup.request('send','');const request=f.sent.filter(x=>x.m==='frontend.screen').at(-1);let issued=0;
 f.startup.api.command=()=>{if(++issued===2)throw Error('local failure');};f.startup.reply(f.reply(request,{cmds:[{type:'send',text:'one'},{type:'copy',text:'two'}]}));f.startup.end();assert.equal(issued,2);assert.equal(f.performed.length,0);
});
test('renderer validation preserves text data and rejects executable tags before decode',async()=>{
 const {validatePresentation}=await import('../../src/web/startup.js');const base={session:{sel:'A',drafts:{A:'日本語'},rid:5},cmds:[],view:{type:'element',tag:'div',key:'current',attrs:[{name:'aria-label',value:'日本語'},{event:'click',action:'select'}],kids:[{type:'text',text:'<script>literal</script>'}]}};
 assert.doesNotThrow(()=>validatePresentation(base));assert.throws(()=>validatePresentation({...base,view:{...base.view,tag:'script'}}),/Invalid presentation/);
});
test('input before greeting survives legacy canonical handoff without a presentation wait',async()=>{
 const f=await fixture();f.startup.request('select','B');f.startup.request('draft','early draft');assert.equal(f.sent.length,0);f.startup.canonicalFrame();f.startup.end();assert.equal(f.adoptions.at(-1).sel,'B');assert.equal(f.adoptions.at(-1).drafts.B,'early draft');
});
test('unsafe retained counters fall back without coercion wrapping or presentation send',async()=>{
 for(const rid of [null,'7',NaN,Infinity,-1,1.5,2**48,2**48-1]){
  const f=await fixture(rid);f.startup.opened();f.greet();f.startup.ready();assert.equal(f.fallbacks.length,1,String(rid));assert.equal(f.sent.length,0,String(rid));assert.equal(f.adoptions.length,0);
 }
});
test('screen send failure cannot strand the independent history path',async()=>{
 const f=await fixture();const send=f.startup.api.send;f.startup.api.send=o=>{if(o.m==='frontend.screen')throw Error('send failed');send(o);};f.greet();f.startup.ready();assert(f.sent.some(x=>x.m==='frontend.history'));
});
test('history send failure falls back boundedly rather than retaining a sent flag forever',async()=>{
 const f=await fixture();const send=f.startup.api.send;f.startup.api.send=o=>{if(o.m==='frontend.history')throw Error('send failed');send(o);};f.greet();f.startup.ready();assert.equal(f.fallbacks.length,1);
});
test('control ids match the numeric Bend Reply contract and are distinct from ordinary ids',async()=>{
 const a=await fixture(),b=await fixture();a.greet();a.startup.ready();b.greet();b.startup.ready();
 const ids=[...a.sent,...b.sent].map(x=>x.id);assert.equal(new Set(ids).size,ids.length);for(const id of ids){assert(Number.isSafeInteger(id));assert(id<2**48&&id>=2**48-8192);assert(id>a.startup.session.rid);}
});
test('canonical handoff does not restore a draft cleared by its unanswered Send',async()=>{
 const f=await fixture();f.greet();f.startup.request('send','');f.startup.api.perform=op=>{f.performed.push(op);const s=f.startup.api.session();f.startup.api.adopt({...s,drafts:{...s.drafts,[op.input.sel]:''}});};
 f.startup.end();assert.equal(f.performed.length,1);assert.equal(f.adoptions.at(-1).drafts.A,'');
});
test('canonical handoff reapplies only edits newer than a captured Send',async()=>{
 const f=await fixture();f.greet();f.startup.request('send','');f.startup.request('draft','new unsent');f.startup.api.perform=op=>{const s=f.startup.api.session();f.startup.api.adopt({...s,drafts:{...s.drafts,[op.input.sel]:''}});};
 f.startup.end();assert.equal(f.adoptions.at(-1).drafts.A,'new unsent');
});
test('old Send Keep cannot erase newer drafts in either selected conversation',async()=>{
 const f=await fixture(),disk=new Map();f.startup.api.local=(a,v,s)=>{if(a==='draft')disk.set(s.sel,v);};f.startup.api.command=c=>{if(c.type==='keep')disk.set(c.thread,c.text);};
 f.greet();f.startup.request('send','');const active=f.sent.filter(x=>x.m==='frontend.screen').at(-1);f.startup.request('draft','A newer');f.startup.request('select','B');f.startup.request('draft','B newer');
 f.startup.reply(f.reply(active,{cmds:[{type:'keep',thread:'A',text:''}]}));assert.equal(disk.get('A'),'A newer');assert.equal(disk.get('B'),'B newer');
});
test('connection replacement keeps unanswered intentions in original order',async()=>{
 const old=await fixture();old.greet();old.startup.request('send','first');const pending=old.startup.pending();old.startup.close();const next=await fixture();next.startup.inherit(pending);next.startup.request('send','second');next.startup.canonicalFrame();next.startup.end();
 assert.deepEqual(next.performed.map(op=>op.value),['first','second']);
});
test('draft refresh is debounced and cannot run after canonical mode',async()=>{
 const f=await fixture();f.greet();f.startup.reply(f.reply());const before=f.sent.length;f.startup.request('draft','a');await f.tick(30);f.startup.request('draft','ab');await f.tick(74);assert.equal(f.sent.length,before);await f.tick(1);assert.equal(f.sent.length,before+1);
 f.startup.end();await f.tick(100);assert.equal(f.sent.length,before+1);
});
