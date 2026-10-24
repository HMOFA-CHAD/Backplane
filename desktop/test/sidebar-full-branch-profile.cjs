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
Object.assign(names,{notifyInfo:root('thin$045actor$058Actor$info$'),notifySheets:root('thin$045actor$058Actor$sheets$'),plain:root('core$047client$058Side$ix$'),mine:root('core$047client$058SIx$mine$'),seq:root('core$047model$058State$seq$'),indexOf:root('core$047thin$058Index$of$'),page:root('core$047thin$058Index$page$')});
if(dependent)Object.assign(names,{commit:root('server$058Cfg$thin$committed$'),signalSeq:root('server$058Cfg$thin$signal_seq$'),bump:root('server$058Cfg$thin$bump$'),live:root('server$058Cfg$thin$live$'),warm:root('server$058Cfg$thin$warm$'),withNotes:root('server$058Cfg$thin$with_notes$'),mailEmpty:root('thin$045mail$058Cache$empty$'),notesEmpty:root('core$047thin$045pace$058Notes$empty$'),mapNew:root('Map$new$')});
const image=[...defs.keys()].some(n=>n.endsWith('thin$045actor$058SidebarImage$key$'));if(image)Object.assign(names,{imageLookup:root('thin$045actor$058SidebarImage$lookup$')});names.streamAppend=root('core$047thin$045live$058Stream$append$');
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
let keyCalls=0,keyMs=0;const keyName=root('thin$045sidebar$058Sidebar$key$revision$');ctx.keyStart=()=>{keyCalls++;return performance.now()};ctx.keyEnd=t=>{keyMs+=performance.now()-t};vm.runInContext(keyName+'=((old)=>(...args)=>{const t=keyStart();try{return old(...args)}finally{keyEnd(t)}})('+keyName+');',ctx);
const shared=[...defs.keys()].some(n=>n.endsWith('thin$045actor$058SidebarImage$key$shared$'));
return {contentTransport:[...defs.keys()].some(n=>n.endsWith('thin$045sidebar$045wire$058Content$send$')),shared,keyCalls:()=>keyCalls,keyMs:()=>keyMs,image,ordinaryDerived:[...defs.keys()].some(n=>n.endsWith('thin$045sidebar$058Sidebar$derived$')),labelReads:()=>labelReads,labelReadMs:()=>labelReadMs,materialized,textCalls:()=>textCalls,textMs:()=>textMs,metadataKey:[...defs.keys()].some(n=>n.endsWith('thin$045sidebar$058Sidebar$key$revision$')),frameCount:()=>frameCount,frameMs:()=>frameMs,dependent,ctx,names,root,nativeNeeded,rawSha256:sha(source),nativeSha256:sha(native),plainCount:()=>plainCount,count:()=>count,atCount:()=>atCount,workCount:()=>workCount,reset:()=>{keyCalls=0;keyMs=0;labelReads=0;labelReadMs=0;count=0;workCount=0;atCount=0;plainCount=0;frameCount=0;frameMs=0;textCalls=0;textMs=0}};
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
 if(process.env.SIDEBAR_NESTED){st=f.apply(st,E('ThreadParentSet',{id:'t45',parent:'t0',at:now-3592}));st=f.apply(st,E('ThreadParentSet',{id:'t90',parent:'t45',at:now-3591}));}
 if(process.env.SIDEBAR_RUNNING)st=f.apply(st,E('TurnChanged',{thread:'t0',state:{$:'../core/model.Running'},at:now-3590}));
 for(const [key,value]of [['onboard.done','1'],['sidebar.view','active']])st=f.apply(st,E('SettingSet',{key,value,at:now-3590}));
 const info=json({models:catalog(Number(process.env.MODEL_LABEL_COUNT||157),'Current label')}),live=json({});
 const p={hub:'synthetic',epoch:'synthetic',generation:'7',target:{kind:'thread',id:'t0'},session:{sel:'t0',rid:100,open:{},drafts:{t0:'Synthetic 日本語 IME draft'},info:{}},action:'flag',value:'settings',requestRevision:1,sidebarRegion:{version:1,token:''},signalRevision:0};
 const actor=f.refresh(nil,true,st,info,live,now,json(p),'synthetic'),cfg=e.dependent?makeCfg(e,st):null,index=f.indexOf(st),ids=f.page(index,'t0',0,32),input=sha(JSON.stringify([st,cfg,actor]));e.reset();
 const cold=measure(()=>render(e,actor,st,index,p,'synthetic',now,ids,f.seq(st)));const coldCalls=e.count(),coldPlainCalls=e.plainCount(),coldTextCalls=e.textCalls();assert.equal(coldTextCalls,1);assert.equal(coldPlainCalls,1,'Cold render derives one plain metadata index');
 assert.equal(sha(JSON.stringify([st,cfg,actor])),input,'Cold render mutated input');assert.equal(coldCalls,1,'Cold render must derive one index');
 const issued=f.output(true,list([cold.value.actor]),cold.value.result,json(p));const coldPlain=Wire.plain(Wire.cbor(bytes(f.encode(issued.result)),KEYS,WORDS));assert.deepEqual(coldPlain,JSON.parse(f.show(issued.result)),'Cold binary decode mismatch');const receiver=sidebarPicture(coldPlain,p,null);assert.equal(receiver.result.session.open.settings,true,'Seed must enter Settings by its normal Open action');const next={...p,session:receiver.result.session,action:'settings-page',value:'appearance'};return {st,info,live,p:next,cfg,issued,cold,coldCalls,coldPlainCalls,coldTextCalls,receiverCache:receiver.cache};
}

function chat(e,s,c){
 const f=e.ctx.f;let st=s.st;const events=c.events||[];for(const event of events)st=f.apply(st,event);
 const cfg=f.commit(s.cfg,list(events),st),rev=f.signalSeq(cfg);assert.equal(rev,c.keep?f.signalSeq(s.cfg):f.seq(st),'Trusted actual commit revision');
 const selected=c.target||'t0',session={...s.p.session,sel:selected,open:{...s.p.session.open,settings:!!c.settings},drafts:{...s.p.session.drafts,[selected]:c.draft||'Synthetic 日本語 IME draft'}};
 const p={...s.p,hub:c.hub||'synthetic',epoch:c.epoch||'synthetic',generation:c.generation||'7',target:{kind:'thread',id:selected},session,action:c.action||'',value:c.value||'',requestRevision:Number(s.receiverCache?.token||1)+1,sidebarRegion:{version:1,token:c.badAck?'99':s.receiverCache?.token||'1',exactContent:!c.oldClient}};if(c.legacy)delete p.sidebarRegion;
 let prior=c.reconnect?nil:s.issued.actors;if(c.notification)prior=list([f[c.notification==='info'?'notifyInfo':'notifySheets'](prior.head,json(c.notification==='info'?{info:{}}:{t:'sheets',items:[]}))]);const clock=c.clock?now+1:now,epoch=c.epoch||'synthetic',info=c.info?json({models:c.capInfo?JSON.stringify({...JSON.parse(catalog(157,'Fresh label')),padding:'q'.repeat(32769)}):catalog(157,'Fresh label'),status:'fresh recipient info'}):s.info;
 let a=f.refresh(prior,true,st,info,s.live,clock,json(p),c.view||'synthetic');if(c.offline)a={...a,ui:{...a.ui,online:false}};
 const ix=f.indexOf(st),ids=f.page(ix,selected,0,32),signals=e.ctx.activity.index(st),input=sha(JSON.stringify([st,prior,a,cfg]));e.reset();
 let stream=f.stream();if(c.stream)stream=f.streamAppend(stream,c.stream,1);const priorImage=(()=>{for(let xs=a.memo;xs.$!=='Nil';xs=xs.tail)if(xs.head.$.endsWith('.SidebarImage'))return xs.head;return null})();
 const measured=measure(()=>e.ctx.f.render(a,true,st,ix,json(p),epoch,clock,ids,stream,rev));
 const counts={signal:e.count(),plain:e.plainCount(),text:e.textCalls(),sidebar:e.frameCount(),key:e.keyCalls()},text=f.show(measured.value.result),logical=bytes(f.encode(measured.value.result));
 assert.equal(input,sha(JSON.stringify([st,prior,a,cfg])),'Mutated input alias');
 const outgoing=measure(()=>f.output(true,list([measured.value.actor]),measured.value.result,json(p))),issued=outgoing.value,enc=measure(()=>bytes(f.encode(issued.result))),wire=enc.value,decoded=Wire.plain(Wire.cbor(wire,KEYS,WORDS));assert.deepEqual(decoded,JSON.parse(f.show(issued.result)),'Native encoder/unchanged decoder mismatch');
 const receipt=sidebarPicture(decoded,p,s.receiverCache),received=receipt.result,full={...received};delete full.sidebarRegion;assert.deepEqual(full,JSON.parse(text),'Actual receiver differs from full original result');
 if(c.body)assert(JSON.stringify(received.shown).includes(c.body),'Actual fresh timeline body absent');
 assert.equal(received.session.drafts[selected],c.action==='send'?'':session.drafts[selected],'Draft/action result changed');assert.equal(received.session.open.settings,!!c.settings,'Settings state changed');
 const settings=!!c.settings||c.action==='settings-page'||(c.action==='flag'&&c.value==='settings'),eligible=!c.action||settings;
 const wantKeys=(!c.action&&!settings)?(e.shared&&f.seq(st)===rev?1:2):1;assert.equal(counts.key,wantKeys,'Exact key serialization call count');
 const miss=!c.keep||c.reconnect||c.epoch||c.view||c.target||c.derivedMissing;const expect=(e.ordinaryDerived&&eligible)||settings?(miss?1:0):1;
 assert.equal(counts.signal,expect,'Raw signal recomputation');assert.equal(counts.plain,expect,'Plain index recomputation');assert.equal(counts.text,expect||c.offline?1:0,'Canonical text recomputation');
 if(!settings){assert.equal(counts.sidebar,e.image&&c.cache==='hit'?0:1,'Only exact ordinary sidebar image may skip construction');if(events.length&&!c.badAck&&!c.legacy&&(!e.contentTransport||c.oldClient))assert(!decoded.sidebarRegion?.base,'Fresh full-sequence history must not use Settings reference');}
 if(c.info){assert(text.includes('Fresh label'),'Fresh catalog missing');const nf=measured.value.actor.ui.info;assert(mapEntries(nf).some(([k,v])=>k==='models'&&v.includes('Fresh label')),'Current accepted model info absent');let tc=null;for(let xs=measured.value.actor.memo;xs.$!=='Nil';xs=xs.tail)if(xs.head.$.endsWith('.SignalText'))tc=xs.head.cache;if(e.ordinaryDerived){assert(tc,'Candidate canonical text memo absent');assert.deepEqual(mapEntries(f.overlay(tc.values,nf)),mapEntries(f.refCache(!c.offline,signals,nf)),'Fresh accepted recipient info overlay differs from original');}else assert.equal(tc,null,'Baseline ordinary renderer saves only its existing picture memo');}
 const images=[];for(let xs=measured.value.actor.memo;xs.$!=='Nil';xs=xs.tail)if(xs.head.$.endsWith('.SidebarImage'))images.push(xs.head);assert(images.length<=1,'Multiple private rendered images');if(e.image&&c.cache==='hit'){assert.equal(images.length,1);assert(priorImage&&images[0].key===priorImage.key,'Reused metadata image key changed');}if(c.oversize||settings)assert.equal(images.length,0,'Disabled/oversize projection retained image');if(e.image&&!settings&&!c.oversize&&!c.action)assert.equal(images.length,1,'Current image must be retained');if(c.stream)assert(JSON.stringify(received.shown).includes(c.stream),'Fresh actual streamed main text absent');
 const memos=[];for(let xs=measured.value.actor.memo;xs.$!=='Nil';xs=xs.tail)memos.push(xs.head.$);for(const kind of ['Signals','SideIndex','SignalText'])assert(memos.filter(x=>x.endsWith('.'+kind)).length<=1,'Duplicate private '+kind);
 if(c.capture)e.last={...s,st,cfg,p:{...p,session:received.session},issued,receiverCache:receipt.cache};
 e.latest={actor:measured.value.actor,result:measured.value.result,p:json(p)};const commands=received.cmds||[];if(c.action==='send'){assert(commands.length>0,'Send must produce an owned command');assert(JSON.stringify(commands).includes('t0'),'Send command owner missing');assert.equal(images.length,0,'Command must discard private image');}
 const sent=[];for(let ms=issued.actors.head.memo;ms.$!=='Nil';ms=ms.tail)if(ms.head.$.endsWith('.SidebarSent'))sent.push(ms.head);assert(sent.length<=1,'Sent retention exceeds one');if(c.action||c.legacy||c.oldClient)assert.equal(sent.length,0,'Disabled exact transport retains sent value');
 return {sentCount:sent.length,outputMs:outgoing.ms,keyMs:e.keyMs(),commandCount:commands.length,imageCount:images.length,privateImageReused:!!(e.image&&c.cache==='hit'),text,logical,wire,signals:JSON.stringify(signals),renderMs:measured.ms,encodeMs:enc.ms,counts,canonicalSequence:f.seq(st),dependencySequence:rev,sentReference:!!decoded.sidebarRegion?.base,wireBytes:wire.length,replySha256:sha(text),wireSha256:sha(wire),logicalSha256:sha(logical),receiverExact:true,freshTimeline:!!c.body,draftPreserved:true,inputImmutable:true};
}




const findings=[];let state='failed',error;
try{
 const engines=[engine(beforeRaw,beforeNative),engine(afterRaw,afterNative)];for(const e of engines)chat(e,seed(e),{keep:true,reconnect:true,capture:true});
 const events=Array.from({length:32},(_,i)=>E('MessagePosted',{thread:'t0',msg:'packaged-branch-'+i,role:{$:'../core/model.Assistant'},text:'Fresh packaged branch timeline '+i+' 日本語 '+('current text '+i+' ').repeat(8),at:now}));
 const cases=[{name:'cold-full',keep:true,reconnect:true},{name:'warm-ref-32',keep:true,cache:'hit',events,body:'Fresh packaged branch timeline 31 日本語'},{name:'visible-change-full',keep:false,events:[E('ThreadRenamed',{id:'t0',title:'Visible packaged current title',at:now})]}];
 for(const c of cases){const rendered=engines.map(e=>chat(e,e.last,c));assert.equal(rendered[0].text,rendered[1].text);assert.deepEqual(rendered[0].logical,rendered[1].logical);assert.deepEqual(rendered[0].wire,rendered[1].wire);assert.deepEqual(rendered[0].counts,rendered[1].counts);const inputs=engines.map(e=>e.latest),identities=inputs.map(x=>sha(JSON.stringify(x))),pairs=[];
  for(let i=0;i<4;i++){const q=[];for(const k of i%2?[1,0]:[0,1]){const e=engines[k],x=inputs[k],m=measure(()=>e.ctx.f.output(true,list([x.actor]),x.result,x.p));q[k]={ms:m.ms,text:e.ctx.f.show(m.value.result),wire:bytes(e.ctx.f.encode(m.value.result)),actor:sha(JSON.stringify(m.value.actors))};assert.equal(sha(JSON.stringify(x)),identities[k])}assert.equal(q[0].text,q[1].text);assert.deepEqual(q[0].wire,q[1].wire);assert.equal(q[0].actor,q[1].actor);pairs.push({beforeMs:q[0].ms,afterMs:q[1].ms,identicalResult:true,identicalNativeWire:true,identicalActor:true,inputImmutable:true,replySha256:sha(q[0].text),wireSha256:sha(q[0].wire),wireBytes:q[0].wire.length,reference:!!JSON.parse(q[0].text).sidebarRegion.base})}
  const counts=engines.map((e,k)=>{const replace=e.root('thin$045sidebar$045wire$058Region$replace$go$');e.ctx.replaceCalls=0;vm.runInContext('globalThis.originalReplace='+replace+';'+replace+'=(...args)=>{replaceCalls++;return originalReplace(...args)};',e.ctx);const x=inputs[k];e.ctx.f.output(true,list([x.actor]),x.result,x.p);vm.runInContext(replace+'=originalReplace;',e.ctx);return e.ctx.replaceCalls});if(c.name==='warm-ref-32')assert.equal(counts[0],counts[1]);else{assert(counts[0]>0);assert.equal(counts[1],0)}findings.push({name:c.name,replacementCalls:{before:counts[0],after:counts[1]},fullLogicalAndNativeBytesExact:true,actualReceiverExact:true,renderSamples:rendered.map(x=>({...x,text:undefined,logical:undefined,wire:undefined,signals:undefined})),pairs});fs.writeFileSync(out+'.partial.json',JSON.stringify({state:'pending',findings},null,2)+'\n')}
 state='passed';
}catch(e){error=e.stack}
const report={state,bun:Bun.version,before:{commit:beforeCommit,rawSha256:sha(fs.readFileSync(beforeRaw)),nativeSha256:sha(fs.readFileSync(beforeNative))},after:{commit:afterCommit,rawSha256:sha(fs.readFileSync(afterRaw)),nativeSha256:sha(fs.readFileSync(afterNative))},findings,error,scope:'Only new actual packaged PR421/full-branch pure guard comparison:12 alternating exact-input Region.output pairs across cold-full/warm32ref/visible-full; complete logical+native outgoing bytes/actor/input/unchanged decoder+receiver. Replacement counts measured outside timings. All raw slower pairs retained; no live ratio. Existing PR421 qualification retained; no rebuild/UI/provider/broad suite.'};fs.writeFileSync(out,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));if(state!=='passed')process.exitCode=1;
