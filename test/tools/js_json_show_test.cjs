// Server-only serializer against the retained, unchanged compiled pure oracle.
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),vm=require('node:vm'),cp=require('node:child_process');
const root=path.resolve(__dirname,'../..'),emit=process.env.JSON_SHOW_REFERENCE_EMIT;
assert(emit,'Supply the retained exact pure reference emit');
const source=fs.readFileSync(emit,'utf8'),defs=new Map();
for(const m of source.matchAll(/^function ([\w$]+)\([^\n]*\) \{[\s\S]*?^\}/gm))defs.set(m[1],m[0]);
function name(tail){const xs=[...defs.keys()].filter(n=>n.endsWith(tail));assert.equal(xs.length,1);return xs[0]}
const show=name('core$047json$058Json$show$'),emitName=name('core$047json$058Json$emit$'),needed=new Set(),todo=[show];
while(todo.length){const n=todo.pop();if(needed.has(n))continue;needed.add(n);for(const m of defs.get(n).matchAll(/[A-Za-z_$][\w$]*/g))if(defs.has(m[0])&&!needed.has(m[0]))todo.push(m[0])}
const ctx=vm.createContext({}),helper=fs.readFileSync(path.join(root,'scripts/js-json-show.js'),'utf8');
vm.runInContext([...needed].map(n=>defs.get(n)).join('\n')+helper+`;globalThis.oracle=${show};globalThis.native=j=>__bpJsonShow(j,oracle);`,ctx,{timeout:10000});
const outcome=fn=>{try{return {kind:'value',value:fn()}}catch(e){return {kind:'throw',value:typeof e==='string'?e:String(e)}}};
function json(v){if(v===null)return {$:'../core/json.Null'};if(typeof v==='string')return {$:'../core/json.Str',text:v};if(typeof v==='boolean')return {$:'../core/json.Flag',value:v};if(typeof v==='number')return {$:'../core/json.Num',raw:String(v)};if(Array.isArray(v)){let items={$:'../core/json.End'};for(const x of [...v].reverse())items={$:'../core/json.Item',head:json(x),tail:items};return {$:'../core/json.Arr',items}}let fields={$:'../core/json.End'};for(const [key,value]of Object.entries(v).reverse())fields={$:'../core/json.Field',key,value:json(value),tail:fields};return {$:'../core/json.Obj',fields}}
function same(name,j){const before=JSON.stringify(j);assert.deepEqual(outcome(()=>ctx.native(j)),outcome(()=>ctx.oracle(j)),name);assert.equal(JSON.stringify(j),before,'Input mutated: '+name)}
test('exact escapes, Unicode/scalar errors, raw lexemes, duplicate keys and arbitrary typed chains',()=>{
 const check=same;
 const strings=['','text','"\\','日本語','🚀','\u2028\u2029','\ud800','\udfff','a\ud800b\udfff','\ud800\udfff'];for(let i=0;i<32;i++)strings.push(String.fromCharCode(i));for(const n of [23,24,255,256,4096])strings.push('x'.repeat(n)+'日本語');
 for(const [i,x]of strings.entries())check('string-'+i,json(x));
 const raw=(kind,fields)=>({$:'../core/json.'+kind,...fields}),end=raw('End',{});for(const n of ['0','-0','1.2','1e+22','01','Infinity','-'])check('raw-number-'+n,raw('Num',{raw:n}));
 for(const [name,j]of [['end',end],['bare-item',raw('Item',{head:json('head'),tail:json(true)})],['bare-field',raw('Field',{key:'x',value:json('v'),tail:end})],['duplicates',raw('Obj',{fields:raw('Field',{key:'x',value:json(1),tail:raw('Field',{key:'x',value:json(2),tail:end})})})],['unusual-object',raw('Obj',{fields:json('not-a-chain')})],['unusual-array',raw('Arr',{items:json(false)})]])check(name,j);
 let random=1234567;function next(){random=(Math.imul(random,1664525)+1013904223)>>>0;return random}function tree(depth){const k=next()%(depth?6:4);if(k===0)return json(null);if(k===1)return json(!!(next()%2));if(k===2)return json(strings[next()%strings.length]);if(k===3)return raw('Num',{raw:['0','-0','1.2','1e9'][next()%4]});if(k===4){let items=end;for(let i=0,n=next()%7;i<n;i++)items=raw('Item',{head:tree(depth-1),tail:items});return raw('Arr',{items})}let fields=end;for(let i=0,n=next()%7;i<n;i++)fields=raw('Field',{key:strings[next()%strings.length],value:tree(depth-1),tail:fields});return raw('Obj',{fields})}
 for(let i=0;i<100;i++)check('mixed-'+i,tree(3));

});
test('non-ASCII raw numbers retain compiled reversal boundaries and error order',()=>{
 const end={$:'../core/json.End'},num=raw=>({$:'../core/json.Num',raw}),item=(head,tail)=>({$:'../core/json.Item',head,tail});
 for(const raw of ['日本語','🚀','\ud800','\udfff','a\ud800b','\udfff\ud800']){
  same('raw-'+JSON.stringify(raw),num(raw));same('raw-chain-'+JSON.stringify(raw),item(num(raw),item(num('\udfff'),end)));
 }
 same('earlier-invalid-field',{$:'../core/json.Field',key:'\ud800',value:num('\udfff'),tail:end});
 same('later-invalid-field',item(num('\ud800'),item(json('\udfff'),end)));
});
test('long valid strings, escaped fields and shared input aliases remain exact',()=>{
 const shared=json('日本語🚀\n\t'.repeat(512));same('shared',{$:'../core/json.Arr',items:{$:'../core/json.Item',head:shared,tail:{$:'../core/json.Item',head:shared,tail:{$:'../core/json.End'}}}});
 same('field-order',json({'a\n\b':'x','a\r\f':'y',ready:true,revision:1234}));
});
test('actual server transform lands once; web stays pure; missing/duplicate/body/callee drift fails before writes',()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'bp-json-show-'));
 try{const input=path.join(dir,'input.js'),min=path.join(dir,'min.js');fs.writeFileSync(input,source);
 cp.execFileSync(process.env.BUN_BINARY||'bun',['build','--minify-whitespace','--minify-syntax','--keep-names','--target=bun',input,'--outfile',min],{stdio:'pipe',timeout:20000});const original=fs.readFileSync(min,'utf8');
 const run=(s,server=true)=>{fs.writeFileSync(min,s);return cp.spawnSync('python3',[path.join(root,'scripts/js-native.py'),...(server?['--server']:[]),min],{encoding:'utf8',timeout:10000})};
 assert.equal(run(original).status,0);const got=fs.readFileSync(min,'utf8');assert.equal(got.split('return __bpJsonShow(').length-1,1);assert(got.includes(`function ${show}$raw(_j_0){return ${emitName}(_j_0,!0,"")}`));
 const syntax=cp.spawnSync(process.execPath,['--input-type=module','--check'],{input:got,encoding:'utf8',timeout:10000});assert.equal(syntax.status,0,syntax.stderr.slice(0,300));
 assert.equal(run(original,false).status,0);assert(!fs.readFileSync(min,'utf8').includes('__bpJsonShow'));
 const definition=`function ${show}(_j_0){return ${emitName}(_j_0,!0,"")}`;assert(original.includes(definition));
 const failures=[original.replace('function '+show+'(','function changedShow('),original+definition,original.replace(definition,definition.replace(',!0,',',!1,')),original.replace(definition,definition.replace(emitName,'wrong$058Json$emit$')),original.replace('function '+emitName+'(','function changedEmit(')];
 for(const s of failures){const result=run(s);assert.notEqual(result.status,0);assert.equal(fs.readFileSync(min,'utf8'),s,'Failed build wrote a partial transform')}
 }finally{fs.rmSync(dir,{recursive:true,force:true})}
});
