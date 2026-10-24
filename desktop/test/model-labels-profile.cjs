// Headless exact packaged-runtime comparison; synthetic metadata only.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {performance}=require('node:perf_hooks');
const {sidebarPicture}=require('../../src/web/sidebar-region.js');
const Wire=require('../../src/web/wire.js');
const cborSource=fs.readFileSync(require('node:path').join(__dirname,'../../src/core/cbor.bend'),'utf8');
const dict=name=>{const m=cborSource.match(new RegExp('def Cbor\\.'+name+'\\(\\) -> List<&2, String>:\\s*(\\[[\\s\\S]*?\\])'));assert(m,'Canonical dictionary missing');return JSON.parse(m[1]);};
const KEYS=dict('keys'),WORDS=dict('words');
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
let count=0,workCount=0,atCount=0,plainCount=0,frameCount=0,frameMs=0,textCalls=0,textMs=0;
const textName=root('core$047signal$058Signal$cache$pairs$');ctx.textStart=()=>{textCalls++;return performance.now()};ctx.textEnd=t=>{textMs+=performance.now()-t};vm.runInContext(textName+'=((old)=>(...args)=>{const t=textStart();try{return old(...args)}finally{textEnd(t)}})('+textName+');',ctx);
const materialized=[...defs.keys()].some(n=>n.endsWith('thin$045signal$045text$058SignalTextCache$build$'));
vm.runInContext('globalThis.f.refCache='+root('core$047signal$058Signal$cache$')+';globalThis.f.mapSet='+root('Map$set$')+';',ctx);
if(materialized)vm.runInContext('globalThis.f.textBuild='+root('thin$045signal$045text$058SignalTextCache$build$')+';globalThis.f.overlay='+root('core$047signal$058Signal$cache$overlay$')+';',ctx);
const frame=root('web$047view$058View$sidebar$frame$');ctx.frameStart=()=>{frameCount++;return performance.now()};ctx.frameEnd=t=>{frameMs+=performance.now()-t};vm.runInContext(frame+'=((old)=>(...args)=>{const t=frameStart();try{return old(...args)}finally{frameEnd(t)}})('+frame+');',ctx);
const plain=root('core$047client$058Side$ix$');ctx.recordPlain=()=>{plainCount++};vm.runInContext(plain+'=((old)=>(...args)=>{recordPlain();return old(...args)})('+plain+');',ctx);
const n=root('core$047signal$058Signal$index$');ctx.recordSignal=()=>{count++};
vm.runInContext(n+'=((old)=>(...args)=>{recordSignal();return old(...args)})('+n+');',ctx);
const w=root('core$047signal$058Signal$cache$work$');ctx.recordWork=()=>{workCount++};vm.runInContext(w+'=((old)=>(...args)=>{recordWork();return old(...args)})('+w+');',ctx);
const at=root('core$047signal$058Signal$at$');ctx.recordAt=()=>{atCount++};vm.runInContext(at+'=((old)=>(...args)=>{recordAt();return old(...args)})('+at+');',ctx);
let rowDepth=0,labelReads=0,labelReadMs=0;
const rowsName=root('web$047view$058View$models$loc$'),aboutName=root('core$047client$058Models$about$');
ctx.enterRows=()=>{rowDepth++};ctx.leaveRows=()=>{rowDepth--};ctx.labelRead=old=>{if(rowDepth>0){const t=performance.now();try{return old()}finally{labelReads++;labelReadMs+=performance.now()-t}}return old()};
vm.runInContext(rowsName+'=((old)=>(...args)=>{enterRows();try{return old(...args)}finally{leaveRows()}})('+rowsName+');'+aboutName+'=((old)=>(...args)=>labelRead(()=>old(...args)))('+aboutName+');',ctx);
return {labelReads:()=>labelReads,labelReadMs:()=>labelReadMs,materialized,textCalls:()=>textCalls,textMs:()=>textMs,metadataKey:[...defs.keys()].some(n=>n.endsWith('thin$045sidebar$058Sidebar$key$revision$')),frameCount:()=>frameCount,frameMs:()=>frameMs,dependent,ctx,names,root,nativeNeeded,rawSha256:sha(source),nativeSha256:sha(native),plainCount:()=>plainCount,count:()=>count,atCount:()=>atCount,workCount:()=>workCount,reset:()=>{labelReads=0;labelReadMs=0;count=0;workCount=0;atCount=0;plainCount=0;frameCount=0;frameMs=0;textCalls=0;textMs=0}};
}
function mapEntries(m){const out=[],stack=[m];while(stack.length){const x=stack.pop();if(x.$==='MLeaf')out.push([x.key,x.val]);else if(x.$==='MNode')stack.push(x.lo,x.hi);else assert.equal(x.$,'MTip');}return out.sort((a,b)=>a[0]<b[0]?-1:a[0]>b[0]?1:0);}
function json(v){if(v===null)return {$:'../core/json.Null'};if(typeof v==='string')return {$:'../core/json.Str',text:v};if(typeof v==='boolean')return {$:'../core/json.Flag',value:v};if(typeof v==='number')return {$:'../core/json.Num',raw:String(v)};if(Array.isArray(v)){let items={$:'../core/json.End'};for(const x of [...v].reverse())items={$:'../core/json.Item',head:json(x),tail:items};return {$:'../core/json.Arr',items};}let fields={$:'../core/json.End'};for(const [key,value]of Object.entries(v).reverse())fields={$:'../core/json.Field',key,value:json(value),tail:fields};return {$:'../core/json.Obj',fields};}

const nil={$:'Nil'},now=1792800000,rows=[],stage={step:'setup'},integration=[];
const list=xs=>xs.reduceRight((tail,head)=>({$:'Con',head,tail}),nil);
const E=(name,fields)=>({$:'../core/model.'+name,...fields});
function bytes(xs){const a=[];for(let x=xs;x.$!=='Nil';x=x.tail)a.push(x.head);return Buffer.from(a)}
function measure(fn){const t=performance.now(),value=fn();return {value,ms:performance.now()-t}}
function makeCfg(e,st){const f=e.ctx.f;return {$:'server.Cfg',home:'/tmp/synthetic-signal-dependencies',web:'',host:'127.0.0.1',port:0,prompt:'',dirs:nil,version:'synthetic',net:null,telemetry:nil,views:list([{$:'server.ThinCache',index:{$:'../core/thin.Built',index:f.indexOf(st)},epoch:'synthetic',revision:1,streams:f.mapNew(),mail:{$:'thin-mail.Built',cache:f.mailEmpty()},waiting:nil,notes:f.notesEmpty(),store:'',signal_seq:f.seq(st)}])}}
function render(e,actor,st,index,p,epoch,clock,ids,revision){return e.ctx.f.render(actor,true,st,index,json(p),epoch,clock,ids,e.ctx.f.stream(),...(e.dependent?[revision]:[]))}
function catalog(n,prefix){const ids=Array.from({length:n},(_,i)=>'synthetic/model-'+i),labels=Object.fromEntries(['',...ids].map((id,i)=>[id||'default',prefix+' '+i+' 日本語']));return JSON.stringify({codex:ids,about:{codex:{labels,efforts:{default:['low','high']}}},claude:['opus']})}
function seed(e){
 const f=e.ctx.f;let st=f.empty();for(let p=0;p<45;p++)st=f.apply(st,E('ProjectCreated',{id:'p'+p,title:'Synthetic project '+p,root:'/tmp/signal-facts-'+p,at:now-3600}));
 for(let i=0;i<2786;i++){st=f.apply(st,E('ThreadCreated',{id:'t'+i,project:'p'+i%45,title:'Synthetic thread '+i,env:{$:'../core/model.Local'},branch:'',worktree:'',provider:'codex',model:'',at:now-3600}));if(i>=32)st=f.apply(st,E('ThreadSettled',{id:'t'+i,manual:false,at:now-3599}));}
 for(const [key,value]of [['onboard.done','1'],['sidebar.view','active']])st=f.apply(st,E('SettingSet',{key,value,at:now-3590}));
 const info=json({models:catalog(Number(process.env.MODEL_LABEL_COUNT||157),'Current label')}),live=json({});
 const p={target:{kind:'thread',id:'t0'},session:{sel:'t0',rid:100,open:{},drafts:{t0:'Synthetic 日本語 IME draft'},info:{}},action:'flag',value:'settings',requestRevision:1,sidebarRegion:{version:1,token:''},signalRevision:0};
 const actor=f.refresh(nil,true,st,info,live,now,json(p),'synthetic'),cfg=e.dependent?makeCfg(e,st):null,index=f.indexOf(st),ids=f.page(index,'t0',0,32),input=sha(JSON.stringify([st,cfg,actor]));e.reset();
 const cold=measure(()=>render(e,actor,st,index,p,'synthetic',now,ids,f.seq(st)));const coldCalls=e.count(),coldPlainCalls=e.plainCount(),coldTextCalls=e.textCalls();assert.equal(coldTextCalls,1);assert.equal(coldPlainCalls,1,'Cold render derives one plain metadata index');
 assert.equal(sha(JSON.stringify([st,cfg,actor])),input,'Cold render mutated input');assert.equal(coldCalls,1,'Cold render must derive one index');
 const issued=f.output(true,list([cold.value.actor]),cold.value.result,json(p));const coldPlain=Wire.plain(Wire.cbor(bytes(f.encode(issued.result)),KEYS,WORDS));assert.deepEqual(coldPlain,JSON.parse(f.show(issued.result)),'Cold binary decode mismatch');const receiver=sidebarPicture(coldPlain,p,null);assert.equal(receiver.result.session.open.settings,true,'Seed must enter Settings by its normal Open action');const next={...p,session:receiver.result.session,action:'settings-page',value:'appearance'};return {st,info,live,p:next,cfg,issued,cold,coldCalls,coldPlainCalls,coldTextCalls,receiverCache:receiver.cache};
}
function run(e,s,scenario){
 const f=e.ctx.f,events=scenario.events||[];let st=s.st;for(const c of events)st=f.apply(st,c);
 const beforeCfg=e.dependent?sha(JSON.stringify(s.cfg)):'';
 const cfg=e.dependent?f.commit(s.cfg,list(events),st):null,revision=e.dependent?f.signalSeq(cfg):f.seq(st);
 if(e.dependent){assert.equal(sha(JSON.stringify(s.cfg)),beforeCfg,'Commit mutated previous config');assert.equal(revision,scenario.keep?f.seq(s.st):f.seq(st),'Actual committed dependency revision wrong');}
 const p={...s.p,session:{...s.p.session,drafts:{t0:scenario.draft||'Synthetic 日本語 IME draft'}},...(scenario.history?{action:'flag',value:'settings'}:{}),requestRevision:2,sidebarRegion:scenario.noAck?{version:1,token:''}:scenario.badAck?{version:1,token:'99'}:{version:1,token:'1'},signalRevision:scenario.forged||0};
 if(scenario.legacy)delete p.sidebarRegion;
 const clock=scenario.sameClock?now:now+1,epoch=scenario.epoch||'synthetic',prior=scenario.reconnect?nil:s.issued.actors;
 let actor=f.refresh(prior,true,st,scenario.info?json({models:catalog(Number(process.env.MODEL_LABEL_COUNT||157),'Current label'),status:'fresh',...(scenario.extraInfo||{})}):s.info,s.live,clock,json(p),scenario.view||'synthetic');if(scenario.offline)actor={...actor,ui:{...actor.ui,online:false}};const index=f.indexOf(st),ids=f.page(index,'t0',0,32);
 if(scenario.mailHidden){const mine=f.mine(f.plain(st),'p1');let present=false;for(let xs=mine;xs.$!=='Nil';xs=xs.tail)if(xs.head.id==='t1')present=true;assert.equal(present,false,'Actual RunSet must hide the mail-run thread');}
 const rawSignals=e.ctx.activity.index(st);if(scenario.bits!==undefined)assert.equal(e.ctx.activity.at(rawSignals,'t0'),scenario.bits,'Fixture must contain actual delegated running work');const raw=JSON.stringify(rawSignals);const old=sha(JSON.stringify([st,prior,actor,cfg]));e.reset();
 const measured=measure(()=>render(e,actor,st,index,p,epoch,clock,ids,revision)),calls=e.count();assert.equal(sha(JSON.stringify([st,prior,actor,cfg])),old,'Render mutated input aliases');
 const frames=e.frameCount(),frameTime=e.frameMs(),textCount=e.textCalls(),textTime=e.textMs();
 const wire=f.output(true,list([measured.value.actor]),measured.value.result,json(p)),text=f.show(measured.value.result),logicalEncoded=bytes(f.encode(measured.value.result));
 const enc=measure(()=>bytes(f.encode(wire.result))),encoded=enc.value,plain=Wire.plain(Wire.cbor(encoded,KEYS,WORDS));assert.deepEqual(plain,JSON.parse(f.show(wire.result)),'Exact native CBOR decoder mismatch');
 const expectRef=!!(e.metadataKey&&scenario.ref&&!scenario.noAck&&!scenario.badAck&&!scenario.legacy);
 if((plain.sidebarRegion?.base||'')!==(expectRef?'1':'')){
  const saved=a=>{for(let xs=a.memo;xs.$!=='Nil';xs=xs.tail)if(xs.head.$.endsWith('.Sidebar'))return xs.head.key;return ''};const k0=saved(s.issued.actors.head),k1=saved(measured.value.actor),a=k0?JSON.parse(k0):{},b=k1?JSON.parse(k1):{};
  stage.finding={candidate:e.metadataKey,frames,priorKeyLength:k0.length,currentKeyLength:k1.length,changedFields:[...new Set([...Object.keys(a),...Object.keys(b)])].filter(k=>JSON.stringify(a[k])!==JSON.stringify(b[k])),receivedBase:plain.sidebarRegion?.base||'',expectedReference:expectRef};
 }
 assert.equal(plain.sidebarRegion?.base||'',expectRef?'1':'','Only acknowledged same-clock history may send a reference');
 const reconstructed=sidebarPicture(plain,p,s.receiverCache).result;
 const reconstructedLogical={...reconstructed};delete reconstructedLogical.sidebarRegion;
 assert.deepEqual(reconstructedLogical,JSON.parse(text),'Actual receiver reconstructed different logical reply');
 assert.equal(frames,scenario.ref&&e.metadataKey?0:1,'Sidebar render reuse count mismatch');
 if(scenario.name==='main-new-labels'){const pending=[plain.shown],labels=[];while(pending.length){const n=pending.pop();if(!n||typeof n!=='object')continue;if(n.type==='element'&&n.tag==='span'&&n.attrs?.some(a=>a.name==='class'&&a.value==='label'))for(const c of n.kids||[])if(c.type==='text')labels.push(c.text);pending.push(...(n.kids||[]));}assert(labels.some(x=>x.startsWith('Fresh label ')),'Fresh model label must reach actual shown row');}
 if(scenario.body)assert(text.includes(scenario.body),'New actual timeline body missing: '+scenario.name);
 let retained=0;for(let m=measured.value.actor.memo;m.$!=='Nil';m=m.tail)if(m.head.$.endsWith('.Signals'))retained++;
 assert.equal(retained,1,'Exactly one bounded actor-private signal index');
 let metadata=0;for(let m=measured.value.actor.memo;m.$!=='Nil';m=m.tail)if(m.head.$.endsWith('.SideIndex'))metadata++;const expectedMetadata=1;assert.equal(metadata,expectedMetadata,'Bounded metadata remains private and singular');
 let textCache=null,textCaches=0;for(let m=measured.value.actor.memo;m.$!=='Nil';m=m.tail)if(m.head.$.endsWith('.SignalText')){textCaches++;textCache=m.head.cache;}assert.equal(textCaches,e.materialized?1:0,'Canonical text memo count');
 const expectedTextCalls=e.materialized?(scenario.keep&&!scenario.reconnect&&!scenario.epoch&&!scenario.view&&!scenario.offline?0:1):1;assert.equal(textCount,expectedTextCalls,'Canonical text construction count mismatch');
 if(e.materialized){const entries=mapEntries(textCache.values);assert.equal(entries.length,2787);assert(entries.every(([k])=>k==='@signal.online'||k.startsWith('@signal:')),'Memo retained recipient info');assert.equal(textCache.online,!scenario.offline);const nf=measured.value.actor.ui.info;const original=JSON.stringify(nf);assert.deepEqual(mapEntries(f.overlay(textCache.values,nf)),mapEntries(f.refCache(!scenario.offline,rawSignals,nf)),'Whole decorated info map differs from original');assert.equal(JSON.stringify(nf),original,'Overlay mutated recipient input');}

 return {rowLabelReads:e.labelReads(),rowLabelReadMs:e.labelReadMs(),text,encoded,logicalEncoded,signals:raw,canonicalTextCalls:textCount,canonicalTextMs:textTime,canonicalTextEntries:textCache?mapEntries(textCache.values).length:0,freshInfoExact:e.materialized?true:undefined,sidebarFrames:frames,sidebarFrameMs:frameTime,receiverExact:true,receiverDecodedFromNativeCbor:true,sentReference:expectRef,wireEncodeMs:enc.ms,renderMs:measured.ms,plainIndexCalls:e.plainCount(),signalIndexCalls:calls,signalLookupCalls:e.atCount(),dependencySequence:revision,canonicalSequence:f.seq(st),timelineBodyPresent:scenario.body?true:undefined,replySha256:sha(text),cborSha256:sha(encoded),cborBytes:encoded.length,fullSidebarSent:!expectRef};
}
let state='failed';try{
 const before=engine(beforeRaw,beforeNative),after=engine(afterRaw,afterNative);before.commitTag=beforeCommit;after.commitTag=afterCommit;assert(before.dependent&&after.dependent&&before.metadataKey&&after.metadataKey&&before.materialized&&after.materialized,'PR412 and requested control/candidate required');stage.step='seed';
 const seeds=[seed(before),seed(after)];assert.equal(before.ctx.f.show(seeds[0].cold.value.result),after.ctx.f.show(seeds[1].cold.value.result),'Cold complete reply mismatch');
 rows.push({scenario:'cold',identicalReply:true,beforeRenderMs:seeds[0].cold.ms,afterRenderMs:seeds[1].cold.ms,beforeSignalIndexCalls:seeds[0].coldCalls,afterSignalIndexCalls:seeds[1].coldCalls,beforePlainIndexCalls:seeds[0].coldPlainCalls,afterPlainIndexCalls:seeds[1].coldPlainCalls,beforeTextCalls:seeds[0].coldTextCalls,afterTextCalls:seeds[1].coldTextCalls});
 const f=after.ctx.f,cfg=seeds[1].cfg,original=f.signalSeq(cfg),originalCfg=sha(JSON.stringify(cfg));
 for(const [name,changed]of [['view invalidation',f.bump(cfg)],['stream update',f.live(cfg,f.mapNew(),'t0')],['warm store',f.warm(cfg,f.index(),f.mailEmpty())],['pacing notes',f.withNotes(cfg,f.notesEmpty())]]){assert.equal(f.signalSeq(changed),original,name+' changed dependency revision');integration.push({name,passed:true});}
 assert.equal(sha(JSON.stringify(cfg)),originalCfg,'Config transforms mutated original');
 const scenarios=[
 {name:'main-warning',sameClock:true,ref:true,history:true,keep:true,body:'Fresh warning',events:[E('ActivityLogged',{thread:'t0',act:'w',tone:'warn',kind:'notice',summary:'Fresh warning',at:now})]},
 {name:'main-assistant',sameClock:true,ref:true,history:true,keep:true,body:'Fresh assistant',events:[E('MessagePosted',{thread:'t0',msg:'a',role:{$:'../core/model.Assistant'},text:'Fresh assistant',at:now})]},
 {name:'main-new-labels',sameClock:true,history:true,keep:true,info:true,extraInfo:{models:catalog(Number(process.env.MODEL_LABEL_COUNT||157),'Fresh label')},body:'New catalog warning',events:[E('ActivityLogged',{thread:'t0',act:'f',tone:'warn',kind:'notice',summary:'New catalog warning',at:now})]},
 {name:'main-malformed-labels',sameClock:true,history:true,keep:true,info:true,extraInfo:{models:JSON.stringify({codex:['a','b'],about:{codex:{labels:{a:17,b:'Fresh B'}}}})},body:'Malformed metadata warning',events:[E('ActivityLogged',{thread:'t0',act:'m',tone:'warn',kind:'notice',summary:'Malformed metadata warning',at:now})]},
 {name:'main-draft-edit',sameClock:true,history:true,keep:true,draft:'Changed 日本語 IME',body:'Draft warning',events:[E('ActivityLogged',{thread:'t0',act:'d',tone:'warn',kind:'notice',summary:'Draft warning',at:now})]},
 {name:'settings-appearance',sameClock:true,ref:true,keep:true},
 {name:'main-reconnect',sameClock:true,history:true,keep:true,reconnect:true,body:'Reconnect warning',events:[E('ActivityLogged',{thread:'t0',act:'r',tone:'warn',kind:'notice',summary:'Reconnect warning',at:now})]},
 {name:'main-open-ask',sameClock:true,history:true,body:'Ask warning',events:[E('AskOpened',{id:'q',thread:'t0',kind:'input',tool:'choose',detail:'Real canonical question',options:'',at:now}),E('ActivityLogged',{thread:'t0',act:'q',tone:'warn',kind:'notice',summary:'Ask warning',at:now})]}
 ];
 for(const scenario of scenarios){if(process.env.SIDEBAR_READ_ONLY&&!process.env.SIDEBAR_READ_ONLY.split(',').includes(scenario.name))continue;if(process.env.SIDEBAR_READ_FROM&&scenarios.findIndex(x=>x.name===scenario.name)<scenarios.findIndex(x=>x.name===process.env.SIDEBAR_READ_FROM))continue;if(!scenario.keep)scenario.sameClock=true;if(scenario.sameClock&&scenario.events)scenario.events=scenario.events.map(c=>({...c,at:now}));stage.step=scenario.name;const results=[run(before,seeds[0],scenario),run(after,seeds[1],scenario)];
  assert.equal(results[0].signals,results[1].signals,'Complete raw signal map changed');assert.equal(results[0].text,results[1].text,'Complete reply mismatch: '+scenario.name);assert.deepEqual(results[0].logicalEncoded,results[1].logicalEncoded,'Exact logical native CBOR mismatch: '+scenario.name);assert.deepEqual(results[0].encoded,results[1].encoded,'Exact native CBOR mismatch: '+scenario.name);
  const expectedSignal=scenario.keep&&!scenario.reconnect&&!scenario.epoch&&!scenario.view?0:1;assert.equal(results[0].signalIndexCalls,expectedSignal,'PR411 revision behavior wrong');assert.equal(results[1].signalIndexCalls,expectedSignal,'Candidate revision behavior wrong');if(!scenario.ref)assert.equal(results[0].signalLookupCalls,results[1].signalLookupCalls,'Signal decoration fresh on misses');
  assert.equal(results[0].plainIndexCalls,expectedSignal,'PR411 metadata behavior wrong');assert.equal(results[1].plainIndexCalls,expectedSignal,'Reuse only unchanged trusted metadata, never owner or epoch replacement');
  if(scenario.history){assert(results[0].rowLabelReads>=1,'Actual old rows required');assert.equal(results[1].rowLabelReads,1,'Provider label metadata read once per nonempty row list');}else assert.equal(results[1].rowLabelReads,0);
  rows.push({scenario:scenario.name,threads:2786,projects:45,identicalReply:true,identicalLogicalCbor:true,identicalWireCbor:true,receiverExact:true,identicalRawSignalMap:true,before:{...results[0],text:undefined,encoded:undefined,logicalEncoded:undefined,signals:undefined},after:{...results[1],text:undefined,encoded:undefined,logicalEncoded:undefined,signals:undefined}});
  fs.writeFileSync(out+'.partial.json',JSON.stringify({state:'pending',integration,rows},null,2)+'\n');
 }
 if(process.env.SIGNAL_TEXT_CAP){stage.step='actual text retention cap';let values=f.mapNew();for(let i=0;i<4096;i++)values=f.mapSet(values,'cap'+i,0);const at=f.textBuild('cap',1,true,values);assert.equal(at.bounded,true);assert.equal(mapEntries(at.values).length,4097);values=f.mapSet(values,'cap4096',0);const over=f.textBuild('cap',2,true,values);assert.equal(over.bounded,false);assert.equal(mapEntries(over.values).length,4098);assert(mapEntries(over.values).some(([k,v])=>k==='@signal:cap4096'&&v==='0'),'Oversize must return complete current output');integration.push({name:'actual4097-entry-cap-and4098-complete-uncached',passed:true});}
 state='passed';
}catch(e){rows.push({step:stage.step,finding:stage.finding,error:e.stack})}
const result={state,only:process.env.SIGNAL_DEPENDENCY_ONLY||null,engine:{bun:Bun.version,runtime:'Bun executing extracted exact packaged pure functions including native map/string/parse/CBOR; candidate uses production Actor.render.revision and Cfg.thin.committed'},before:{commit:beforeCommit,rawSha256:sha(fs.readFileSync(beforeRaw)),nativeSha256:sha(fs.readFileSync(beforeNative))},after:{commit:afterCommit,rawSha256:sha(fs.readFileSync(afterRaw)),nativeSha256:sha(fs.readFileSync(afterNative))},integration,rows,scope:'Exact packaged Bun1.3.10 same-input comparison against PR413 for once-per-row-list current provider-label extraction. Synthetic2786threads/45projects/32active with a157-model or explicitly selected1-model catalog; no real model/provider call. Old/current full replies, native logical and outgoing CBOR, unchanged real decoder/sidebar receiver, raw signals and input immutability checked. Fresh/malformed catalogs, current draft, real canonical ask and connection ownership cases preserve current output. No cache, transport, timer, revision or ownership changes. Native wrappers affect timings; all raw pairs retained including slower tiny-label cases. No actual-profile click/INP or universal speedup claim.'};
fs.writeFileSync(out,JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));if(state!=='passed')process.exitCode=1;
