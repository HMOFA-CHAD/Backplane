'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),crypto=require('node:crypto');
const bundle=process.env.BP_ROUTE_BEND_BUNDLE;
assert(bundle,'Set BP_ROUTE_BEND_BUNDLE to the pinned retained-emission fixture; see README.md');
const plain=v=>JSON.parse(JSON.stringify(v));let compiled;
function actualBend(){
 if(compiled)return compiled;const bytes=fs.readFileSync(bundle),text=bytes.toString('utf8'),stop=text.lastIndexOf('var WIU=0;');assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'),'9c7fb73cee7f7f42ff48e65e1eb7c08d33aa2c2cb41314e0cde55d5b0a71598a','Retained emitted exports must be exact');assert(stop>0,'Retained suite boundary missing');
 compiled=vm.runInNewContext('(function(){'+text.slice(0,stop)+';return {Web:FL,plain:Wf};})()',{console:{log(){throw Error('Old suite must never execute');}},TextEncoder,TextDecoder,Buffer,URL,performance,crypto:crypto.webcrypto},{timeout:10000});return compiled;
}
async function adapters(){
 const {Web:App,plain:decode}=actualBend(),{preservePresentationRoute,presentationTarget,ThinHost}=await import('../../src/web/thin-host.js');
 const host=fs.readFileSync(path.join(__dirname,'../../src/web/host.js'),'utf8'),scope={App,Wire:{plain:decode},presentationJson:v=>App.presentation_json(JSON.stringify(v)),preservePresentationRoute,presentationTarget};
 const choice=host.match(/const choosePresentation = \(session, action, value\) => \{[\s\S]*?\n\};/)[0];
 const choose=vm.runInNewContext('(function(){'+choice+';return choosePresentation;})()',scope);scope.choosePresentation=choose;
 const prepare=host.slice(host.indexOf('choice: choosePresentation, prepare:'),host.indexOf('selection: (target, session)'));
 const ack=host.slice(host.indexOf('ack: (session, reply)'),host.indexOf('decode: shown =>'));
 const local=vm.runInNewContext('({'+prepare+ack+'})',scope);return {...local,choose,App,decode,presentationTarget,preservePresentationRoute,ThinHost};
}
const session=tab=>({sel:'thread-b',rid:2,drafts:{'thread-b':'original 日本語'},outbox:{},open:{},info:{},adding:false,panel:false,wantNew:false,error:'',note:'',route:{kind:'bot-tab',bot:'b',tab}});
test('RED retained actual emitted Web draft/Send/ACK exports drop manual Chat route',()=>{
 const{Web:App,plain:decode}=actualBend(),s=session('chat'),j=v=>App.presentation_json(JSON.stringify(v));
 const draft=decode(App.presentation_choice('draft',j(s),'typed 日本語'));assert.equal(draft.route,undefined);assert.equal(draft.drafts['thread-b'],'typed 日本語');
 assert.equal(decode(App.presentation_prepare(j(s),j(s),'send')).route,undefined);
 assert.equal(decode(App.presentation_reply(j(s),j({t:'reply',id:123,ok:true,result:{}}))).route,undefined);
});
test('GREEN actual host callback preserves Chat for typed and deliberately empty drafts',async()=>{
 const a=await adapters(),s=session('chat');for(const text of ['typed 日本語 👩‍💻','']){const out=a.choose(s,'draft',text);assert.deepEqual(plain(out.route),s.route);assert.equal(out.drafts['thread-b'],text);}
});
test('captured Send keeps captured route and draft without dispatching any command',async()=>{
 const a=await adapters(),captured=session('chat'),current=session('mail');captured.drafts['thread-b']='captured';current.drafts['thread-b']='newer';
 const out=a.prepare(current,captured,'send');assert.deepEqual(plain(out.route),captured.route);assert.equal(out.drafts['thread-b'],'captured');assert.equal(current.drafts['thread-b'],'newer');
});
test('ordinary ACK retains current route; explicit thread selection discards old bot route',async()=>{
 const a=await adapters(),s=session('chat');assert.deepEqual(plain(a.ack(s,{t:'reply',id:123,ok:true,result:{}}).route),s.route);
 const chosen=a.choose(s,'select','ordinary-thread');assert.equal(chosen.route,undefined);assert.deepEqual(a.presentationTarget(chosen),{kind:'thread',id:'ordinary-thread'});
});
test('closed route validation and real selection changes cannot borrow a bot tab',async()=>{
 const a=await adapters(),s=session('chat');for(const route of [{...s.route,extra:'bad'},{...s.route,tab:'invented'},{...s.route,bot:''}]){const before={...s,route};assert.equal(a.preservePresentationRoute(before,{sel:s.sel}).route,undefined);assert.deepEqual(a.presentationTarget(before),{kind:'thread',id:s.sel});}
 assert.equal(a.preservePresentationRoute(s,{sel:'newly-created-thread'}).route,undefined);assert.deepEqual(a.presentationTarget(s),{kind:'bot',id:'b'});
});
test('actual ThinHost draft/update descriptors retain Chat and Unicode across invalidation',async()=>{
 const a=await adapters(),{ThinViews,VIEW_LIMITS}=await import('../../src/web/thin.js');let current=session('chat'),refresh;const sent=[];
 const host=new a.ThinHost({hub:'https://fixture',cid:'x',now:()=>0,session:()=>current,target:a.presentationTarget,choice:a.choose,prepare:a.prepare,ack:a.ack,counter(){},send:r=>sent.push(r),sessionChanged:s=>current=s,local(){},state(){},view(){},decode:x=>x,anchor:()=>({id:'',offset:0}),blocked(){},command(){},draftRefresh:f=>refresh=f},ThinViews,2**47);
 const reply=(request,tab)=>({t:'reply',id:request.id,ok:true,result:{version:1,hub:'https://fixture',generation:'7',epoch:'e',requestRevision:request.p.requestRevision,target:request.p.target,viewId:'bot-view',viewRevision:'1',renderer:'web',remoteReady:true,shown:{type:'text',text:'chat'},session:{...plain(request.p.session),route:session(tab).route},cmds:[],window:{ids:[],older:'',hasMore:false,anchor:{id:'',offset:0},partial:[]}}});
 host.greeting({t:'view',version:1,renderer:'web',generation:'7',epoch:'e',limits:{...VIEW_LIMITS}});assert.deepEqual(sent[0].p.target,{kind:'bot',id:'b'});host.receive(reply(sent.at(-1),'chat'));
 host.request('draft','typed 日本語');refresh();assert.equal(sent.at(-1).m,'view.update');assert.deepEqual(plain(sent.at(-1).p.session.route),session('chat').route);assert.equal(current.drafts['thread-b'],'typed 日本語');
 host.receive(reply(sent.at(-1),'chat'));host.ack({t:'reply',id:987,ok:true,result:{}});assert.deepEqual(plain(current.route),session('chat').route);
});
test('late old Mailroom update cannot overtake accepted Chat tab and newer local draft',async()=>{
 const a=await adapters(),{ThinViews,VIEW_LIMITS}=await import('../../src/web/thin.js');let current=session('mail');const sent=[],views=[];
 const host=new a.ThinHost({hub:'https://fixture',cid:'x',now:()=>0,session:()=>current,target:a.presentationTarget,choice:a.choose,prepare:a.prepare,ack:a.ack,counter(){},send:r=>sent.push(r),sessionChanged:s=>current=s,local(){},state(){},view:n=>views.push(n),decode:x=>x,anchor:()=>({id:'',offset:0}),blocked(){},command(){}},ThinViews,2**47);
 const reply=(request,tab)=>({t:'reply',id:request.id,ok:true,result:{version:1,hub:'https://fixture',generation:'7',epoch:'e',requestRevision:request.p.requestRevision,target:request.p.target,viewId:'bot-view',viewRevision:'1',renderer:'web',remoteReady:true,shown:{type:'text',text:tab},session:{...plain(request.p.session),route:session(tab).route},cmds:[],window:{ids:[],older:'',hasMore:false,anchor:{id:'',offset:0},partial:[]}}});
 host.greeting({t:'view',version:1,renderer:'web',generation:'7',epoch:'e',limits:{...VIEW_LIMITS}});host.receive(reply(sent.at(-1),'mail'));host.update();const old=sent.at(-1);
 host.request('bot-tab','chat');host.receive(reply(sent.at(-1),'chat'));host.request('draft','new local text');const count=views.length;host.receive(reply(old,'mail'));assert.equal(views.length,count);assert.equal(current.route.tab,'chat');assert.equal(current.drafts['thread-b'],'new local text');
});
