const {test} = require('node:test');
const assert = require('node:assert/strict');

async function fixture() {
  const {ThinHost} = await import(process.env.THIN_HOST_MODULE || '../../src/web/thin-host.js');
  const {ThinViews, VIEW_LIMITS} = await import('../../src/web/thin.js');
  const route = tab => ({kind:'bot-tab', bot:'bub', tab});
  let session = {sel:'bub-chat', rid:1, drafts:{'bub-chat':'kept draft'}, route:route('chat')};
  const sent = [], shown = [], settled = [];
  const host = new ThinHost({hub:'https://fixture', cid:'fixture', now:()=>0, session:()=>session,
    target:()=>({kind:'bot', id:'bub'}), counter(){}, send:r=>sent.push(r),
    prepare:s=>s, choice:(s,a,v)=>a==='select'?{...s,sel:v,route:undefined}:s,
    sessionChanged:s=>{session=s;}, local(){}, state(){}, blocked(){},
    anchor:()=>({id:'',offset:0}), decode:n=>n, view:n=>shown.push(n.text), command(){},
  }, ThinViews, 2**47);
  const reply = (request, tab, revision='2') => ({t:'reply', id:request.id, ok:true, result:{
    version:1, hub:'https://fixture', generation:'7', epoch:'actual', renderer:'web',
    requestRevision:request.p.requestRevision, target:request.p.target,
    viewId:request.p.viewId || 'bot-view', viewRevision:revision, remoteReady:true,
    session:{...request.p.session, route:route(tab)}, cmds:[], shown:{type:'text',text:tab},
    window:{ids:[],older:'',hasMore:false,anchor:{id:'',offset:0},partial:[]},
  }});
  host.greeting({t:'view',version:1,renderer:'web',generation:'7',epoch:'actual',limits:{...VIEW_LIMITS}});
  host.receive(reply(sent.at(-1),'chat','1'));
  const changed = () => host.receive({t:'view.changed',version:1,generation:'7',epoch:'actual',
    viewId:'bot-view',target:{kind:'bot',id:'bub'},viewRevision:'2'});
  return {host,sent,shown,settled,reply,changed,getSession:()=>session};
}

test('a hub update during bot-tab cannot supersede the tab with the old route', async()=>{
  const f=await fixture();
  f.host.request('bot-tab','memory',ok=>f.settled.push(ok));
  const action=f.sent.at(-1);
  f.changed();f.host.update();
  assert.equal(f.sent.length,2,'background reads wait for the tab action');
  f.host.receive(f.reply(action,'memory'));
  assert.equal(f.shown.at(-1),'memory');assert.deepEqual(f.settled,[true]);
  const refresh=f.sent.at(-1);
  assert.equal(refresh.m,'view.update');assert.equal(refresh.p.session.route.tab,'memory');
  f.host.receive(f.reply(refresh,'memory'));
  assert.equal(f.getSession().route.tab,'memory');assert.equal(f.getSession().drafts['bub-chat'],'kept draft');
});

test('queued bot-tab precedes deferred refresh; refresh uses the last accepted tab', async()=>{
  const f=await fixture();
  f.host.request('bot-tab','space');const first=f.sent.at(-1);
  f.changed();f.host.request('bot-tab','browser');
  f.host.receive(f.reply(first,'space'));
  const second=f.sent.at(-1);
  assert.equal(second.m,'view.action');assert.equal(second.p.value,'browser');
  assert.equal(f.sent.filter(r=>r.m==='view.update').length,0,'no old-route read between tab actions');
  f.changed();f.host.receive(f.reply(second,'browser'));
  const refresh=f.sent.at(-1);assert.equal(refresh.m,'view.update');assert.equal(refresh.p.session.route.tab,'browser');
  f.host.receive(f.reply(refresh,'browser'));assert.equal(f.shown.at(-1),'browser');
});

test('bot-tab deferral does not give its old response authority over a new selection', async()=>{
  const f=await fixture();
  f.host.request('bot-tab','memory');const old=f.sent.at(-1);f.changed();
  f.host.request('select','other');const selected=f.sent.at(-1);
  // The fixture uses a bot target; a real selection callback supplies its new
  // target. Selection revision still prevents this old tab picture adopting.
  f.host.receive(f.reply(selected,'chat'));const count=f.shown.length;
  f.host.receive(f.reply(old,'memory'));
  assert.equal(f.shown.length,count);assert.equal(f.getSession().route.tab,'chat');
});
