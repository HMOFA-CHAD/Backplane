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
const still=[...defs.keys()].some(n=>n.endsWith('thin$045actor$058Memo$reply$clock$'));
Object.assign(names,{memoKey:root('thin$045actor$058Memo$key$'),memoReply:root(still?'thin$045actor$058Memo$reply$clock$':'thin$045actor$058Memo$reply$'),remember:root(still?'thin$045actor$058Rendered$remember$clock$':'thin$045actor$058Rendered$remember$')});
if(still)names.stillAllowed=root('thin$045still$045picture$058Picture$allowed$');else Object.assign(names,{lean:root('thin$045actor$058Actor$lean$')});
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
const kernel=constants+code+'\nglobalThis.f={'+Object.entries(names).map(([k,n])=>k+':'+n).join(',')+'};';const ctx=vm.createContext({});vm.runInContext(kernel,ctx,{timeout:10000});

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
return {kernel,still,contentTransport:[...defs.keys()].some(n=>n.endsWith('thin$045sidebar$045wire$058Content$send$')),shared,keyCalls:()=>keyCalls,keyMs:()=>keyMs,image,ordinaryDerived:[...defs.keys()].some(n=>n.endsWith('thin$045sidebar$058Sidebar$derived$')),labelReads:()=>labelReads,labelReadMs:()=>labelReadMs,materialized,textCalls:()=>textCalls,textMs:()=>textMs,metadataKey:[...defs.keys()].some(n=>n.endsWith('thin$045sidebar$058Sidebar$key$revision$')),frameCount:()=>frameCount,frameMs:()=>frameMs,dependent,ctx,names,root,nativeNeeded,rawSha256:sha(source),nativeSha256:sha(native),plainCount:()=>plainCount,count:()=>count,atCount:()=>atCount,workCount:()=>workCount,reset:()=>{keyCalls=0;keyMs=0;labelReads=0;labelReadMs=0;count=0;workCount=0;atCount=0;plainCount=0;frameCount=0;frameMs=0;textCalls=0;textMs=0}};
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
function complete(e,s,c){
 const f=e.f;let st=s.st;for(const event of c.events||[])st=f.apply(st,event);
 const cfg=f.commit(s.cfg,list(c.events||[]),st),revision=f.signalSeq(cfg),selected=c.target||'t0',clock=now+(c.clock||0),view=c.view||'synthetic',anchor=c.anchor||0;
 const info=c.info?json({models:catalog(157,'Changed label')}):s.info;
 const session={...s.p.session,sel:selected,open:{...s.p.session.open,settings:false},drafts:{...s.p.session.drafts,[selected]:c.draft||'Synthetic 日本語 IME draft'}};
 const p={...s.p,target:{kind:'thread',id:selected},session,action:c.action||'',value:c.value||'',requestRevision:c.revision||10,viewRevision:'fresh-view-revision',sidebarRegion:{version:1,token:s.receiverCache?.token||'1',exactContent:true}};
 let stream=f.stream();if(c.stream)stream=f.streamAppend(stream,c.stream,1);
 const prior=c.reconnect?nil:s.issued.actors,ix=f.indexOf(st),ids=f.page(ix,selected,anchor,32),pJson=json(p),requestIdentity=sha(JSON.stringify(p));
 const begin=performance.now(),infoKey=e.still?f.show(info):f.show(f.lean(info))+'|models:'+[...(JSON.parse(f.show(info)).models||'')].length,key=f.memoKey(f.seq(st),infoKey,pJson,anchor,view,true,selected);
 const cached=e.still?f.memoReply(prior.$==='Nil'?nil:prior.head.memo,true,key,clock*1000+2,clock,true,stream,selected,p.epoch,json(p.target),{$:'../core/i18n.En'}):f.memoReply(prior.$==='Nil'?nil:prior.head.memo,true,key,clock*1000+2,true,stream,selected,p.epoch,json(p.target),{$:'../core/i18n.En'});
 let actors=prior,res,renderCalls=0;
 if(cached.$==='Some')res=cached.value;
 else{renderCalls++;const a=f.refresh(prior,true,st,info,s.live,clock,pJson,view),rendered=f.render(a,true,st,ix,pJson,p.epoch,clock,ids,stream,revision),remembered=e.still?f.remember(rendered,key,clock*1000+2,clock,stream,true,pJson):f.remember(rendered,key,clock*1000+2,stream);actors=list([remembered.actor]);res=remembered.result}
 const renderedMs=performance.now()-begin,logical=f.show(res),outputBegin=performance.now(),issued=f.output(true,actors,res,pJson),wire=bytes(f.encode(issued.result)),outputAndEncodeMs=performance.now()-outputBegin;
 const decoded=Wire.plain(Wire.cbor(wire,KEYS,WORDS)),receipt=sidebarPicture(decoded,p,s.receiverCache),full={...receipt.result};delete full.sidebarRegion;
 assert.deepEqual(JSON.parse(f.show(issued.result)),decoded,'Outgoing native decoder parity');assert.deepEqual(full,JSON.parse(logical),'Unchanged receiver must restore the complete picture');assert.equal(receipt.result.session.drafts[selected],session.drafts[selected]);assert.equal(sha(JSON.stringify(p)),requestIdentity,'Request mutation');if(c.body)assert(logical.includes(c.body),'Fresh actual main/sidebar content missing');
 const memos=[];for(let ms=issued.actors.head.memo;ms.$!=='Nil';ms=ms.tail)if(ms.head.$.endsWith('.Still')||ms.head.$.endsWith('.Memo'))memos.push(ms.head);assert(memos.length<=1,'More than one complete private picture');
 return {next:{...s,st,cfg,info,issued,p:{...p,session:receipt.result.session},receiverCache:receipt.cache},sample:{name:c.name,cacheHit:cached.$==='Some',renderCalls,renderedMs,outputAndEncodeMs,keyBytes:Buffer.byteLength(key),replySha256:sha(logical),wireSha256:sha(wire),wireBytes:wire.length,canonicalRevision:f.seq(st),dependencyRevision:revision,privatePictures:memos.length,stillPicture:memos.some(x=>x.$.endsWith('.Still')),currentClock:clock,receiverExact:true,draftPreserved:true,freshContent:!!c.body},logical,wire,ui:JSON.stringify(issued.actors.head.ui)};
}
try{
 const engines=[engine(beforeRaw,beforeNative),engine(afterRaw,afterNative)];
 for(const e of engines){chat(e,seed(e),{keep:true,reconnect:true,capture:true});const ctx=vm.createContext({});vm.runInContext(e.kernel,ctx,{timeout:10000});e.f=ctx.f;}
 const group=process.env.STILL_GROUP||'base';let states=engines.map(e=>e.last);
 const prime={name:'cold-prime'};const primes=engines.map((e,k)=>complete(e,states[k],prime));assert.equal(primes[0].logical,primes[1].logical);assert.deepEqual(primes[0].wire,primes[1].wire);states=primes.map(x=>x.next);
 const events=Array.from({length:32},(_,i)=>E('MessagePosted',{thread:'t0',msg:'still-history-'+i,role:{$:'../core/model.Assistant'},text:'Fresh still history '+i+' 日本語 '+('body '+i+' ').repeat(8),at:now}));
 let cases=group==='base'?[{name:'same-exact-clock',hit:true},{name:'transport-revision-only',revision:11,hit:true},{name:'changed-Japanese-draft',draft:'Fresh 日本語 composition',hit:false},{name:'fresh-history32',events,body:'Fresh still history 31 日本語',hit:false},{name:'same-fresh-history-read',hit:true}]:group==='controls'?[{name:'next-clock',clock:1,hit:false},{name:'same-next-clock',clock:1,hit:true},{name:'same-length-model-info',info:true,body:'Changed label',hit:false},{name:'other-target',target:'t1',hit:false},{name:'other-view',view:'other-view',hit:false},{name:'older-page-anchor',anchor:1,hit:false}]:group==='stream'?[{name:'Settings-action',action:'flag',value:'settings',hit:false},{name:'new-live-stream',stream:'Fresh actual streamed response',body:'Fresh actual streamed response',hit:false},{name:'updated-live-stream',stream:'Fresh actual streamed response longer',body:'Fresh actual streamed response longer'}]:[];
 if(group==='controls'&&process.env.STILL_CONTINUE==='1')cases=[{name:'same-length-model-info-only',info:true,body:'Changed label',hit:false},{name:'other-target',target:'t1',hit:false},{name:'other-view',target:'t1',view:'other-view',hit:false},{name:'older-page-anchor',target:'t1',view:'other-view',anchor:1,hit:false}];
 for(const c of cases){const pair=engines.map((e,k)=>complete(e,states[k],c));assert.equal(pair[0].logical,pair[1].logical,'Complete baseline/candidate result differs: '+c.name);assert.deepEqual(pair[0].wire,pair[1].wire,'Native outgoing bytes differ: '+c.name);assert.equal(pair[0].ui,pair[1].ui,'Authoritative actor Ui differs: '+c.name);if(c.hit!==undefined)assert.equal(pair[1].sample.cacheHit,c.hit,'Candidate exact-key/clock path: '+c.name);if(!c.stream)assert.equal(pair[0].sample.cacheHit,false,'PR422 has no no-stream memo reuse');findings.push({name:c.name,before:pair[0].sample,after:pair[1].sample,fullLogicalExact:true,nativeWireExact:true,actorUiExact:true});states=pair.map(x=>x.next);fs.writeFileSync(out+'.partial.json',JSON.stringify({state:'pending',group,findings},null,2)+'\n')}
 if(group==='caps'){
  const f=engines[1].f,p=json({target:{kind:'thread',id:'t0'},action:''}),blank=f.stream(),res=json({remoteReady:true,cmds:[],shown:{type:'text',text:'small'},session:{},window:{}});
  for(const [name,n,want]of [['key-at-cap',32768,true],['key-over-cap',32769,false]]){assert.equal(f.stillAllowed(true,p,res,blank,'q'.repeat(n)),want);findings.push({name,eligible:want,actualNativeCap:true})}
  function sized(n){const base={remoteReady:true,cmds:[],shown:{type:'text',text:''},session:{},window:{}};base.shown.text='q'.repeat(n-Buffer.byteLength(JSON.stringify(base)));const typed=json(base);assert.equal(Buffer.byteLength(f.show(typed)),n);return typed}
  for(const [name,n,want]of [['picture-at-cap',262144,true],['picture-over-cap',262145,false]]){assert.equal(f.stillAllowed(true,p,sized(n),blank,'owned'),want);findings.push({name,eligible:want,actualNativeCap:true})}
 }
 state='passed';
}catch(e){error=e.stack}
const report={state,bun:Bun.version,group:process.env.STILL_GROUP||'base',before:{source:beforeCommit,raw:sha(fs.readFileSync(beforeRaw)),native:sha(fs.readFileSync(beforeNative))},after:{source:afterCommit,raw:sha(fs.readFileSync(afterRaw)),native:sha(fs.readFileSync(afterNative))},findings,error,scope:'Only current actual packaged PR422/still-picture complete key/memo/render/output/native-CBOR/unchanged receiver parity and clocks/drafts/fresh history/info/target/anchor/action/stream/caps. Key+memo+refresh+render+remember timings exclude identical prepared index/page retrieval, output/encoding reported separately. All raw slow samples retained; no live ratio or UI/provider/build.'};fs.writeFileSync(out,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));if(state!=='passed')process.exitCode=1;
