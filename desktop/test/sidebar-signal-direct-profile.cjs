// Headless exact packaged-runtime comparison; synthetic metadata only.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {performance}=require('node:perf_hooks');
const [out,beforeRaw,beforeNative,beforeCommit,afterRaw,afterNative,afterCommit]=process.argv.slice(2);assert(out&&afterCommit);
const sha=x=>crypto.createHash('sha256').update(x).digest('hex');
function engine(file,stamped){
const source=fs.readFileSync(file,'utf8'),defs=new Map();
for(const m of source.matchAll(/^function ([\w$]+)\([^\n]*\) \{[\s\S]*?^\}$/gm))defs.set(m[1],m[0]);
const root=tail=>{const a=[...defs.keys()].filter(n=>n.endsWith(tail));assert.equal(a.length,1,tail);return a[0]};
const names={empty:root('core$047model$058State$empty$'),apply:root('core$047model$058State$apply$'),index:root('core$047thin$058Index$empty$'),stream:root('core$047thin$045live$058Stream$blank$'),refresh:root('thin$045actor$058Actor$refresh$'),render:root('thin$045actor$058Actor$render$'),show:root('core$047json$058Json$show$'),encode:root('core$047cbor$058Cbor$encode$'),encText:root('core$047cbor$058Enc$text$'),encHead:root('core$047cbor$058Enc$head$'),output:root('thin$045sidebar$045wire$058Region$output$'),sidebar:root('web$047sidebar$045slot$058Slot$sidebar$')};
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
let count=0,workCount=0;
const n=root('core$047signal$058Signal$index$');ctx.recordSignal=()=>{count++};
vm.runInContext(n+'=((old)=>(...args)=>{recordSignal();return old(...args)})('+n+');',ctx);
const w=root('core$047signal$058Signal$cache$work$');ctx.recordWork=()=>{workCount++};vm.runInContext(w+'=((old)=>(...args)=>{recordWork();return old(...args)})('+w+');',ctx);
return {ctx,names,root,nativeNeeded,rawSha256:sha(source),nativeSha256:sha(native),count:()=>count,workCount:()=>workCount,reset:()=>{count=0;workCount=0}};
}
function json(v){if(v===null)return {$:'../core/json.Null'};if(typeof v==='string')return {$:'../core/json.Str',text:v};if(typeof v==='boolean')return {$:'../core/json.Flag',value:v};if(typeof v==='number')return {$:'../core/json.Num',raw:String(v)};if(Array.isArray(v)){let items={$:'../core/json.End'};for(const x of [...v].reverse())items={$:'../core/json.Item',head:json(x),tail:items};return {$:'../core/json.Arr',items};}let fields={$:'../core/json.End'};for(const [key,value]of Object.entries(v).reverse())fields={$:'../core/json.Field',key,value:json(value),tail:fields};return {$:'../core/json.Obj',fields};}

const nil={$:'Nil'},now=1792800000,rows=[],stage={step:'setup'};
const get=(o,key)=>{for(let f=o.fields;f&&f.$.endsWith('.Field');f=f.tail)if(f.key===key)return f.value;throw Error('Missing Json field '+key)};
function bytes(xs){const a=[];for(let x=xs;x.$!=='Nil';x=x.tail)a.push(x.head);return Buffer.from(a)}
function measure(fn){const t=performance.now(),value=fn();return {value,ms:performance.now()-t}}
function seed(e){
 const f=e.ctx.f;let st=f.empty();for(let p=0;p<45;p++)st=f.apply(st,{$:'../core/model.ProjectCreated',id:'p'+p,title:'Synthetic project '+p,root:'/tmp/signal-facts-'+p,at:now-3600});
 for(let i=0;i<2786;i++){st=f.apply(st,{$:'../core/model.ThreadCreated',id:'t'+i,project:'p'+i%45,title:'Synthetic thread '+i,env:{$:'../core/model.Local'},branch:'',worktree:'',provider:'codex',model:'',at:now-3600});if(i>=32)st=f.apply(st,{$:'../core/model.ThreadSettled',id:'t'+i,manual:false,at:now-3599});}
 for(const [key,value]of [['onboard.done','1'],['sidebar.view','active']])st=f.apply(st,{$:'../core/model.SettingSet',key,value,at:now-3590});
 const info=json({models:JSON.stringify({codex:['gpt-6.1-sol'],claude:['opus']})}),live=json({});
 const p={target:{kind:'thread',id:'t0'},session:{sel:'t0',rid:100,open:{settings:true},drafts:{t0:'Synthetic 日本語 IME draft'},info:{}},action:'settings-page',value:'appearance',requestRevision:1,sidebarRegion:{version:1,token:''}};
 const actor=f.refresh(nil,true,st,info,live,now,json(p),'synthetic');const input=sha(JSON.stringify(st));e.reset();
 const cold=measure(()=>f.render(actor,true,st,f.index(),json(p),'synthetic',now,nil,f.stream()));const coldCalls=e.count(),coldWork=e.workCount();
 assert.equal(sha(JSON.stringify(st)),input,'Canonical input mutated');assert.equal(coldCalls,1,'Cold render must derive one index');
 const issued=f.output(true,{$:'Con',head:cold.value.actor,tail:nil},cold.value.result,json(p));
 return {st,info,live,p,issued,cold,coldCalls,coldWork};
}
function run(e,s,scenario){
 const f=e.ctx.f;let st=s.st;for(const c of scenario.events||[])st=f.apply(st,c);
 const p={...s.p,session:{...s.p.session,drafts:{t0:scenario.draft||'Synthetic 日本語 IME draft'}},requestRevision:2,sidebarRegion:{version:1,token:'1'}};
 const clock=now+(scenario.age||1),epoch=scenario.epoch||'synthetic';
 const info=scenario.info?json({...scenario.info,models:JSON.stringify({codex:['gpt-6.1-sol'],claude:['opus']})}):s.info;
 const prior=scenario.reconnect?nil:s.issued.actors;
 const actor=f.refresh(prior,true,st,info,s.live,clock,json(p),'synthetic');
 const signalT0=e.ctx.activity.at(e.ctx.activity.index(st),'t0');
 if(scenario.bits!==undefined)assert.equal(signalT0,scenario.bits,'Canonical fixture must produce expected activity');
 const old=sha(JSON.stringify([st,prior,actor]));e.reset();
 const render=measure(()=>f.render(actor,true,st,f.index(),json(p),epoch,clock,nil,f.stream()));
 const calls=e.count(),parsedWork=e.workCount();assert.equal(sha(JSON.stringify([st,prior,actor])),old,'Render mutated input aliases');
 const wire=f.output(true,{$:'Con',head:render.value.actor,tail:nil},render.value.result,json(p));
 const text=f.show(render.value.result),encoded=bytes(f.encode(wire.result)),plain=JSON.parse(f.show(wire.result));
 assert.equal(plain.sidebarRegion.base,'','Clock/event miss must keep full sidebar transport');
 const memo=render.value.actor.memo;let signals=0;for(let m=memo;m.$!=='Nil';m=m.tail)if(m.head.$==='thin-actor.Signals')signals++;
 // Constructor module labels are intentionally checked by suffix: the import
 // root may name this module relative to main in a packaged build.
 let retained=0;for(let m=memo;m.$!=='Nil';m=m.tail)if(m.head.$.endsWith('.Signals'))retained++;
 return {text,encoded,signalT0,renderMs:render.ms,signalIndexCalls:calls,parsedWorkCalls:parsedWork,retainedSignalMemos:retained,replySha256:sha(text),cborSha256:sha(encoded),cborBytes:encoded.length,clockMissSentFull:true};
}
let state='failed';try{
 const before=engine(beforeRaw,beforeNative),after=engine(afterRaw,afterNative);stage.step='seed';
 const seeds=[seed(before),seed(after)];assert.equal(before.ctx.f.show(seeds[0].cold.value.result),after.ctx.f.show(seeds[1].cold.value.result),'Cold full reply mismatch');
 rows.push({scenario:'cold',identicalReply:true,beforeRenderMs:seeds[0].cold.ms,afterRenderMs:seeds[1].cold.ms,beforeSignalIndexCalls:seeds[0].coldCalls,afterSignalIndexCalls:seeds[1].coldCalls,beforeParsedWorkCalls:seeds[0].coldWork,afterParsedWorkCalls:seeds[1].coldWork});
 const E=(name,fields)=>({$:'../core/model.'+name,...fields});
 const scenarios=[
  {name:'clock-only',expected:0},
  {name:'time-age-boundary',age:86400*40,expected:0},
  {name:'current-model-info-and-draft',info:{'models.v':'42','connection.status':'fresh'},draft:'fresh composed 日本語',expected:0},
  {name:'tool-approval',bits:2,events:[E('AskOpened',{id:'a',thread:'t0',kind:'approval',tool:'tool',detail:'Allow',options:'',at:now+1})],expected:1},
  {name:'question-closed',bits:0,events:[E('AskOpened',{id:'a',thread:'t0',kind:'input',tool:'tool',detail:'Choose',options:'',at:now+1}),E('AskClosed',{id:'a',answer:'yes',at:now+2})],expected:1},
  {name:'owned-watch',bits:1,events:[E('WorkSet',{thread:'t0',kind:'watch',rows:'w\twatching\t\tbuild\twatch'.replaceAll('\\t','\t'),at:now+1})],expected:1},
  {name:'failure',bits:2,events:[E('TurnChanged',{thread:'t0',state:{$:'../core/model.Failed'},at:now+1})],expected:1},
  {name:'reconnect',reconnect:true,expected:1},
  {name:'epoch-change',epoch:'new-epoch',expected:1},
  {name:'reserved-info-fallback',info:{'@signal:ghost':'3'},expected:0,fallback:true}
 ];
 for(const scenario of scenarios){stage.step=scenario.name;const results=[run(before,seeds[0],scenario),run(after,seeds[1],scenario)];
  assert.equal(results[0].text,results[1].text,'Complete reply mismatch: '+scenario.name);assert.deepEqual(results[0].encoded,results[1].encoded,'Exact CBOR mismatch: '+scenario.name);
  assert.equal(results[0].signalIndexCalls,scenario.expected,'Baseline retains PR407 revision behavior');assert.equal(results[0].parsedWorkCalls,1,'Baseline must reconstruct from strings');assert.equal(results[1].parsedWorkCalls,scenario.fallback?1:0,'Direct numeric path or explicit fallback');assert.equal(results[1].signalIndexCalls,scenario.expected,'Candidate wrong revision reuse: '+scenario.name);assert.equal(results[1].retainedSignalMemos,1,'Exactly one bounded private index');
  rows.push({scenario:scenario.name,threads:2786,projects:45,identicalReply:true,identicalCbor:true,before:{...results[0],text:undefined,encoded:undefined},after:{...results[1],text:undefined,encoded:undefined}});
  fs.writeFileSync(out+'.partial.json',JSON.stringify({state:'pending',rows},null,2)+'\n');
 }
 state='passed';
}catch(e){rows.push({step:stage.step,error:e.stack})}
const result={state,engine:{bun:Bun.version,runtime:'Bun executing extracted exact packaged pure functions including native map/string/parse/CBOR; no reference substitution'},before:{commit:beforeCommit,rawSha256:sha(fs.readFileSync(beforeRaw)),nativeSha256:sha(fs.readFileSync(beforeNative))},after:{commit:afterCommit,rawSha256:sha(fs.readFileSync(afterRaw)),nativeSha256:sha(fs.readFileSync(afterNative))},rows,scope:'One bounded paired synthetic2786-thread/45-project/32-active exact packaged-runtime comparison of direct numeric activity projection versus PR407, with explicit legacy reserved-info fallback. Complete replies, native CBOR and input immutability checked. No IO module factory, hub, user profile/history, UI/provider or live speedup/INP claim. Timing samples include wrapper overhead and are not a stable live latency ratio.'};
fs.writeFileSync(out,JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));if(state!=='passed')process.exitCode=1;
