// Headless exact packaged-runtime comparison; synthetic metadata only.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {performance}=require('node:perf_hooks');
const [out,beforeRaw,beforeNative,beforeCommit,afterRaw,afterNative,afterCommit]=process.argv.slice(2);assert(out&&afterCommit);
const sha=x=>crypto.createHash('sha256').update(x).digest('hex');
function engine(file,stamped){
const source=fs.readFileSync(file,'utf8'),defs=new Map();
for(const m of source.matchAll(/^function ([\w$]+)\([^\n]*\) \{[\s\S]*?^\}$/gm))defs.set(m[1],m[0]);
const root=tail=>{const a=[...defs.keys()].filter(n=>n.endsWith(tail));assert.equal(a.length,1,tail);return a[0]};
const dependent=[...defs.keys()].some(n=>n.endsWith('thin$045actor$058Actor$render$revision$'));
const names={empty:root('core$047model$058State$empty$'),apply:root('core$047model$058State$apply$'),index:root('core$047thin$058Index$empty$'),stream:root('core$047thin$045live$058Stream$blank$'),refresh:root('thin$045actor$058Actor$refresh$'),render:root(dependent?'thin$045actor$058Actor$render$revision$':'thin$045actor$058Actor$render$'),show:root('core$047json$058Json$show$'),encode:root('core$047cbor$058Cbor$encode$'),encText:root('core$047cbor$058Enc$text$'),encHead:root('core$047cbor$058Enc$head$'),output:root('thin$045sidebar$045wire$058Region$output$'),sidebar:root('web$047sidebar$045slot$058Slot$sidebar$')};
Object.assign(names,{plain:root('core$047client$058Side$ix$'),mine:root('core$047client$058SIx$mine$'),seq:root('core$047model$058State$seq$'),indexOf:root('core$047thin$058Index$of$'),page:root('core$047thin$058Index$page$')});
if(dependent)Object.assign(names,{commit:root('server$058Cfg$thin$committed$'),signalSeq:root('server$058Cfg$thin$signal_seq$'),bump:root('server$058Cfg$thin$bump$'),live:root('server$058Cfg$thin$live$'),warm:root('server$058Cfg$thin$warm$'),withNotes:root('server$058Cfg$thin$with_notes$'),mailEmpty:root('thin$045mail$058Cache$empty$'),notesEmpty:root('core$047thin$045pace$058Notes$empty$'),mapNew:root('Map$new$')});
const needed=new Set(),todo=Object.values(names);while(todo.length){const n=todo.pop();if(needed.has(n))continue;needed.add(n);for(const m of defs.get(n).matchAll(/[A-Za-z_$][\w$]*/g))if(defs.has(m[0])&&!needed.has(m[0]))todo.push(m[0]);}

const native=fs.readFileSync(stamped,'utf8'),acorn=require('/home/h/.bun/install/cache/acorn@8.16.0@@@1/dist/acorn.js');
const ast=acorn.parse(native,{ecmaVersion:'latest',sourceType:'module'}),nativeDefs=new Map(),nativeNodes=new Map();
// Bun packages the compiled module inside a module factory. Locate its
// lexical block without evaluating that factory or any IO initializer.
let moduleScope=null;function locate(n,parent){if(!n||typeof n!=='object')return;if(n.type==='FunctionDeclaration'&&n.id?.name===names.render)moduleScope=parent;for(const [k,v] of Object.entries(n)){if(k==='start'||k==='end')continue;if(Array.isArray(v)){for(const c of v)locate(c,n)}else if(v&&typeof v==='object')locate(v,n)}}locate(ast,null);assert(moduleScope?.type==='BlockStatement','Compiled module lexical scope missing');
const declarations=[...ast.body,...moduleScope.body];
for(const node of declarations)if(node.type==='FunctionDeclaration'){nativeDefs.set(node.id.name,native.slice(node.start,node.end));nativeNodes.set(node.id.name,node);}
// Inspection-only helpers were tree-shaken from the package; they run outside the measured renderer.
const inspectionOnly=[root('web$047sidebar$045slot$058Slot$sidebar$'),root('web$047sidebar$045slot$058Slot$one$')];for(const n of inspectionOnly)if(!nativeDefs.has(n)){nativeDefs.set(n,defs.get(n));nativeNodes.set(n,acorn.parse(defs.get(n),{ecmaVersion:'latest'}).body[0]);}
// Follow actual identifier references, never names occurring in strings or
// property keys. Textual matching can accidentally pull in an IO factory.
function references(node){const found=new Set();function walk(n,parent,key){if(!n||typeof n!=='object')return;if(n.type==='Literal')return;if(n.type==='Identifier'){
 if(!((parent?.type==='MemberExpression'&&key==='property'&&!parent.computed)||(parent?.type==='Property'&&key==='key'&&!parent.computed)))found.add(n.name);return;
}for(const [k,v]of Object.entries(n)){if(k==='start'||k==='end')continue;if(Array.isArray(v)){for(const c of v)walk(c,n,k)}else if(v&&typeof v==='object')walk(v,n,k)}}walk(node,null,'');return found}
const nativeNeeded=new Set(),nativeTodo=Object.values(names);while(nativeTodo.length){const n=nativeTodo.pop();if(nativeNeeded.has(n))continue;assert(nativeDefs.has(n),'Packaged function missing: '+n);nativeNeeded.add(n);for(const name of references(nativeNodes.get(n)))if(nativeDefs.has(name)&&!nativeNeeded.has(name))nativeTodo.push(name);}
// Only referenced pure module constants are admitted. IO initializers never run.
const code=[...nativeNeeded].map(n=>nativeDefs.get(n)).join('\n'),tokens=new Set([...nativeNeeded].flatMap(n=>[...references(nativeNodes.get(n))]));let constants='';
for(const node of declarations)if(node.type==='VariableDeclaration')for(const d of node.declarations)if(d.id.type==='Identifier'&&tokens.has(d.id.name)){
 assert(d.id.name==='__bpParseMemo'||(d.id.name==='f32_round'&&d.init?.type==='FunctionExpression')||(/^TAB_[0-9]+$/.test(d.id.name)&&d.init?.type==='ArrayExpression'&&d.init.elements.every(x=>x?.type==='Literal'&&typeof x.value==='number'))||(d.init&&['Literal','UnaryExpression','BinaryExpression'].includes(d.init.type)),'Unexpected non-pure referenced constant: '+d.id.name);
 constants+='const '+native.slice(d.start,d.end)+';\n';
}
assert(nativeNeeded.has('__bpBit')&&nativeNeeded.has('__bpOrd')&&nativeNeeded.has('__bpParsed'),'Real packaged native helpers required');
const ctx=vm.createContext({});vm.runInContext(constants+code+'\nglobalThis.f={'+Object.entries(names).map(([k,n])=>k+':'+n).join(',')+'};',ctx,{timeout:10000});

vm.runInContext('globalThis.activity={index:'+root('core$047signal$058Signal$index$')+',at:'+root('core$047signal$058Signal$at$')+'};',ctx);
let count=0,workCount=0,atCount=0,plainCount=0,plainMs=0;
const plain=root('core$047client$058Side$ix$');ctx.recordPlain=()=>{plainCount++};ctx.plainNow=()=>performance.now();ctx.plainTime=ms=>{plainMs+=ms};vm.runInContext(plain+'=((old)=>(...args)=>{recordPlain();const at=plainNow();try{return old(...args)}finally{plainTime(plainNow()-at)}})('+plain+');',ctx);
const n=root('core$047signal$058Signal$index$');ctx.recordSignal=()=>{count++};
vm.runInContext(n+'=((old)=>(...args)=>{recordSignal();return old(...args)})('+n+');',ctx);
const w=root('core$047signal$058Signal$cache$work$');ctx.recordWork=()=>{workCount++};vm.runInContext(w+'=((old)=>(...args)=>{recordWork();return old(...args)})('+w+');',ctx);
const at=root('core$047signal$058Signal$at$');ctx.recordAt=()=>{atCount++};vm.runInContext(at+'=((old)=>(...args)=>{recordAt();return old(...args)})('+at+');',ctx);
return {dependent,ctx,names,root,nativeNeeded,rawSha256:sha(source),nativeSha256:sha(native),plainMs:()=>plainMs,plainCount:()=>plainCount,count:()=>count,atCount:()=>atCount,workCount:()=>workCount,reset:()=>{count=0;workCount=0;atCount=0;plainCount=0;plainMs=0}};
}
function json(v){if(v===null)return {$:'../core/json.Null'};if(typeof v==='string')return {$:'../core/json.Str',text:v};if(typeof v==='boolean')return {$:'../core/json.Flag',value:v};if(typeof v==='number')return {$:'../core/json.Num',raw:String(v)};if(Array.isArray(v)){let items={$:'../core/json.End'};for(const x of [...v].reverse())items={$:'../core/json.Item',head:json(x),tail:items};return {$:'../core/json.Arr',items};}let fields={$:'../core/json.End'};for(const [key,value]of Object.entries(v).reverse())fields={$:'../core/json.Field',key,value:json(value),tail:fields};return {$:'../core/json.Obj',fields};}

const nil={$:'Nil'},now=1792800000,rows=[],stage={step:'setup'},integration=[];
const list=xs=>xs.reduceRight((tail,head)=>({$:'Con',head,tail}),nil);
const E=(name,fields)=>({$:'../core/model.'+name,...fields});
function bytes(xs){const a=[];for(let x=xs;x.$!=='Nil';x=x.tail)a.push(x.head);return Buffer.from(a)}
function measure(fn){const t=performance.now(),value=fn();return {value,ms:performance.now()-t}}
function makeCfg(e,st){const f=e.ctx.f;return {$:'server.Cfg',home:'/tmp/synthetic-signal-dependencies',web:'',host:'127.0.0.1',port:0,prompt:'',dirs:nil,version:'synthetic',net:null,telemetry:nil,views:list([{$:'server.ThinCache',index:{$:'../core/thin.Built',index:f.indexOf(st)},epoch:'synthetic',revision:1,streams:f.mapNew(),mail:{$:'thin-mail.Built',cache:f.mailEmpty()},waiting:nil,notes:f.notesEmpty(),store:'',signal_seq:f.seq(st)}])}}
function render(e,actor,st,index,p,epoch,clock,ids,revision){return e.ctx.f.render(actor,true,st,index,json(p),epoch,clock,ids,e.ctx.f.stream(),...(e.dependent?[revision]:[]))}
function seed(e){
 const f=e.ctx.f;let st=f.empty();for(let p=0;p<45;p++)st=f.apply(st,E('ProjectCreated',{id:'p'+p,title:'Synthetic project '+p,root:'/tmp/signal-facts-'+p,at:now-3600}));
 for(let i=0;i<2786;i++){st=f.apply(st,E('ThreadCreated',{id:'t'+i,project:'p'+i%45,title:'Synthetic thread '+i,env:{$:'../core/model.Local'},branch:'',worktree:'',provider:'codex',model:'',at:now-3600}));if(i>=32)st=f.apply(st,E('ThreadSettled',{id:'t'+i,manual:false,at:now-3599}));}
 for(const [key,value]of [['onboard.done','1'],['sidebar.view','active']])st=f.apply(st,E('SettingSet',{key,value,at:now-3590}));
 const info=json({models:JSON.stringify({codex:['gpt-6.1-sol'],claude:['opus']})}),live=json({});
 const p={target:{kind:'thread',id:'t0'},session:{sel:'t0',rid:100,open:{settings:true},drafts:{t0:'Synthetic 日本語 IME draft'},info:{}},action:'settings-page',value:'appearance',requestRevision:1,sidebarRegion:{version:1,token:''},signalRevision:0};
 const actor=f.refresh(nil,true,st,info,live,now,json(p),'synthetic'),cfg=e.dependent?makeCfg(e,st):null,index=f.indexOf(st),ids=f.page(index,'t0',0,32),input=sha(JSON.stringify([st,cfg,actor]));e.reset();
 const cold=measure(()=>render(e,actor,st,index,p,'synthetic',now,ids,f.seq(st)));const coldCalls=e.count(),coldPlainCalls=e.plainCount();assert.equal(coldPlainCalls,1,'Cold render derives one plain metadata index');
 assert.equal(sha(JSON.stringify([st,cfg,actor])),input,'Cold render mutated input');assert.equal(coldCalls,1,'Cold render must derive one index');
 const issued=f.output(true,list([cold.value.actor]),cold.value.result,json(p));return {st,info,live,p,cfg,issued,cold,coldCalls,coldPlainCalls};
}
function run(e,s,scenario){
 const f=e.ctx.f,events=scenario.events||[];let st=s.st;for(const c of events)st=f.apply(st,c);
 const beforeCfg=e.dependent?sha(JSON.stringify(s.cfg)):'';
 const cfg=e.dependent?f.commit(s.cfg,list(events),st):null,revision=e.dependent?f.signalSeq(cfg):f.seq(st);
 if(e.dependent){assert.equal(sha(JSON.stringify(s.cfg)),beforeCfg,'Commit mutated previous config');assert.equal(revision,scenario.keep?f.seq(s.st):f.seq(st),'Actual committed dependency revision wrong');}
 const p={...s.p,session:{...s.p.session,drafts:{t0:scenario.draft||'Synthetic 日本語 IME draft'}},...(scenario.history?{action:'flag',value:'settings'}:{}),requestRevision:2,sidebarRegion:{version:1,token:'1'},signalRevision:scenario.forged||0};
 const clock=now+1,epoch=scenario.epoch||'synthetic',prior=scenario.reconnect?nil:(scenario.dropMetadata?withoutMetadata(s.issued.actors):s.issued.actors);
 const actor=f.refresh(prior,true,st,s.info,s.live,clock,json(p),'synthetic'),index=f.indexOf(st),ids=f.page(index,'t0',0,32);
 if(scenario.mailHidden){const mine=f.mine(f.plain(st),'p1');let present=false;for(let xs=mine;xs.$!=='Nil';xs=xs.tail)if(xs.head.id==='t1')present=true;assert.equal(present,false,'Actual RunSet must hide the mail-run thread');}
 const rawSignals=e.ctx.activity.index(st);if(scenario.bits!==undefined)assert.equal(e.ctx.activity.at(rawSignals,'t0'),scenario.bits,'Fixture must contain actual delegated running work');const raw=JSON.stringify(rawSignals);const old=sha(JSON.stringify([st,prior,actor,cfg]));e.reset();
 const measured=measure(()=>render(e,actor,st,index,p,epoch,clock,ids,revision)),calls=e.count();assert.equal(sha(JSON.stringify([st,prior,actor,cfg])),old,'Render mutated input aliases');
 const wire=f.output(true,list([measured.value.actor]),measured.value.result,json(p)),text=f.show(measured.value.result),encoded=bytes(f.encode(wire.result)),plain=JSON.parse(f.show(wire.result));
 assert.equal(plain.sidebarRegion.base,'','Full canonical state/clock miss must send full sidebar');
 if(scenario.body)assert(text.includes(scenario.body),'New actual timeline body missing: '+scenario.name);
 let retained=0;for(let m=measured.value.actor.memo;m.$!=='Nil';m=m.tail)if(m.head.$.endsWith('.Signals'))retained++;
 assert.equal(retained,1,'Exactly one bounded actor-private signal index');
 let metadata=0;for(let m=measured.value.actor.memo;m.$!=='Nil';m=m.tail)if(m.head.$.endsWith('.SideIndex'))metadata++;const expectedMetadata=afterCommit===e.commitTag?1:0;assert.equal(metadata,expectedMetadata,'Bounded metadata remains private and singular');
 return {text,encoded,signals:raw,renderMs:measured.ms,plainIndexMs:e.plainMs(),plainIndexCalls:e.plainCount(),signalIndexCalls:calls,signalLookupCalls:e.atCount(),dependencySequence:revision,canonicalSequence:f.seq(st),timelineBodyPresent:scenario.body?true:undefined,replySha256:sha(text),cborSha256:sha(encoded),cborBytes:encoded.length,clockMissSentFull:true};
}
function withoutMetadata(actors){
 const actor=actors.head,kept=[];for(let ms=actor.memo;ms.$!=='Nil';ms=ms.tail)if(!ms.head.$.endsWith('.SideIndex'))kept.push(ms.head);
 return {...actors,head:{...actor,memo:list(kept)}};
}
let state='failed';try{
 const candidate=engine(afterRaw,afterNative);candidate.commitTag=afterCommit;
 const s=seed(candidate);
 for(let round=0;round<4;round++){
  stage.step='paired-system-history-'+round;
  const scenario={name:'system-history',keep:true,history:true,body:'Fresh synthetic system',events:[E('MessagePosted',{thread:'t0',msg:'system1',role:{$:'../core/model.System'},text:'Fresh synthetic system',at:now+1})]};
  let warm,cold;const order=round%2?['warm','forced-miss']:['forced-miss','warm'];
  for(const mode of order){const result=run(candidate,s,{...scenario,dropMetadata:mode==='forced-miss'});if(mode==='warm')warm=result;else cold=result;}
  assert.equal(cold.plainIndexCalls,1);assert.equal(warm.plainIndexCalls,0);
  assert.equal(cold.text,warm.text);assert.deepEqual(cold.encoded,warm.encoded);assert.equal(cold.signals,warm.signals);
  rows.push({round,order,identicalReply:true,identicalCbor:true,identicalRawSignalMap:true,forcedMiss:{...cold,text:undefined,encoded:undefined,signals:undefined},warm:{...warm,text:undefined,encoded:undefined,signals:undefined}});
  fs.writeFileSync(out+'.partial.json',JSON.stringify({state:'pending',rows},null,2)+'\n');
 }
 state='passed';
}catch(e){rows.push({step:stage.step,error:e.stack})}
const result={state,only:process.env.SIGNAL_DEPENDENCY_ONLY||null,engine:{bun:Bun.version,runtime:'Bun executing extracted exact packaged pure functions including native map/string/parse/CBOR; candidate uses production Actor.render.revision and Cfg.thin.committed'},before:{commit:beforeCommit,rawSha256:sha(fs.readFileSync(beforeRaw)),nativeSha256:sha(fs.readFileSync(beforeNative))},after:{commit:afterCommit,rawSha256:sha(fs.readFileSync(afterRaw)),nativeSha256:sha(fs.readFileSync(afterNative))},integration,rows,scope:'Four bounded alternating-order same-artifact pairs resolving mixed system-message renderer samples. Only the private SideIndex memo is omitted in the forced-miss control; state/revision/owner/UI/request/raw-signal cache/clock unchanged. Exact full reply/raw signal/native CBOR and input aliases checked. Direct plain-index inclusive CPU attributed separately from total renderer. All original timings retained. Not live latency/INP, no compiler/service/UI/provider.'};
fs.writeFileSync(out,JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));if(state!=='passed')process.exitCode=1;
