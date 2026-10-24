// Existing server-only exact-text memo, against the unchanged compiled parser.
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),cp=require('node:child_process');
const root=path.resolve(__dirname,'../..'),emit=process.env.JSON_PARSE_REFERENCE_EMIT;
assert(emit,'Supply the retained exact pure parser emit');
const source=fs.readFileSync(emit,'utf8'),defs=new Map();
for(const m of source.matchAll(/^function ([\w$]+)\([^\n]*\) \{[\s\S]*?^\}/gm))defs.set(m[1],m[0]);
const matches=[...defs.keys()].filter(n=>n.endsWith('core$047json$058Json$parse$'));assert.equal(matches.length,1);const parse=matches[0],needed=new Set(),todo=[parse];
while(todo.length){const n=todo.pop();if(needed.has(n))continue;needed.add(n);for(const m of defs.get(n).matchAll(/[A-Za-z_$][\w$]*/g))if(defs.has(m[0])&&!needed.has(m[0]))todo.push(m[0])}
const helper=cp.execFileSync('python3',['-c','import ast,sys; t=ast.parse(open(sys.argv[1]).read()); print(next(ast.literal_eval(n.value) for n in t.body if isinstance(n,ast.Assign) and any(isinstance(x,ast.Name) and x.id=="PARSE_HELPER" for x in n.targets)))',path.join(root,'scripts/js-native.py')],{encoding:'utf8',timeout:10000});
let calls=0;const ctx=vm.createContext({record:()=>calls++});
vm.runInContext([...needed].map(n=>defs.get(n)).join('\n')+helper+`;globalThis.raw=${parse};globalThis.cached=s=>__bpParsed(s,x=>{record();return raw(x)});globalThis.cache=__bpParseMemo;`,ctx,{timeout:10000});
function reset(){ctx.cache.clear();calls=0}
function outcome(fn){try{return {kind:'value',value:fn()}}catch(e){return {kind:'throw',value:typeof e==='string'?e:String(e)}}}
function same(s){const expected=outcome(()=>ctx.raw(s)),actual=outcome(()=>ctx.cached(s));assert.deepEqual(actual,expected);return actual}
const quoted=n=>'"'+'x'.repeat(n-2)+'"';
test('only inputs at or above1024 enter the existing exact-text cache, including prior16KiB inputs',()=>{
 for(const n of [0,1,1023,1024,1025,3233,10515,16383,16384]){
  reset();const s=n===0?'':n===1?'0':quoted(n);assert.equal(s.length,n);same(s);same(s);assert.equal(calls,n<1024?2:1);assert.equal(ctx.cache.size,n<1024?0:1);
 }
});
test('fresh equal-length catalog text misses, exact repeated text hits, and consuming a cached value leaves it unchanged',()=>{
 reset();const cat=label=>JSON.stringify({codex:['m1'],about:{codex:{labels:{default:label,padding:'p'.repeat(1600)}}}}),a=cat('A 日本語'),b=cat('B 日本語');assert.equal(a.length,b.length);
 const first=same(a).value;const before=JSON.stringify(first);same(a);assert.equal(calls,1);const second=same(b).value;assert.equal(calls,2);assert.notEqual(JSON.stringify(first),JSON.stringify(second));assert.equal(JSON.stringify(first),before);same(a);assert.equal(calls,2);
});
test('failed parses and Unicode/escaped inputs match pure outcomes; thrown parser errors are never cached',()=>{
 for(const s of ['{broken'+' '.repeat(1100),'"'+'日本語🚀\\n\\t'.repeat(200)+'"','"\\ud800'+ ' '.repeat(1100)+'"','[1,2,'+' '.repeat(1100)]){
  reset();const a=same(s);same(s);assert.equal(calls,a.kind==='throw'?2:1);assert.equal(ctx.cache.size,a.kind==='throw'?0:1);
 }
 for(const s of [undefined,null,123,true,{}]){reset();same(s);same(s);assert.equal(ctx.cache.size,0);assert.equal(calls,2)}
});
test('all newly eligible text still retains at most8 entries with original FIFO eviction and no hit promotion',()=>{
 reset();const values=Array.from({length:10},(_,i)=>JSON.stringify({id:i,padding:'x'.repeat(1100)}));
 for(let i=0;i<8;i++){same(values[i]);assert.equal(ctx.cache.size,i+1)}
 same(values[0]);assert.equal(calls,8);same(values[8]);assert.equal(ctx.cache.size,8);assert(!ctx.cache.has(values[0]));assert(ctx.cache.has(values[1]));same(values[9]);assert.equal(ctx.cache.size,8);assert(!ctx.cache.has(values[1]));same(values[0]);assert.equal(calls,11);assert.equal(ctx.cache.size,8);
});
