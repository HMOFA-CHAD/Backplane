// New server primitive against the exact compiled pure encoder, never a hub.
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),vm=require('node:vm'),cp=require('node:child_process');
const root=path.resolve(__dirname,'../..'),emit=process.env.CBOR_REFERENCE_EMIT;
assert(emit,'Supply the retained exact reference emit');
const source=fs.readFileSync(emit,'utf8'),defs=new Map();
for(const m of source.matchAll(/^function ([\w$]+)\([^\n]*\) \{[\s\S]*?^\}$/gm))defs.set(m[1],m[0]);
function name(tail){const xs=[...defs.keys()].filter(n=>n.endsWith(tail));assert.equal(xs.length,1);return xs[0];}
const text=name('core$047cbor$058Enc$text$'),head=name('core$047cbor$058Enc$head$'),encode=name('core$047cbor$058Cbor$encode$');
const needed=new Set(),todo=[text,head,encode];while(todo.length){const n=todo.pop();if(needed.has(n))continue;needed.add(n);for(const m of defs.get(n).matchAll(/[A-Za-z_$][\w$]*/g))if(defs.has(m[0])&&!needed.has(m[0]))todo.push(m[0]);}
const ctx=vm.createContext({});vm.runInContext([...needed].map(n=>defs.get(n)).join('\n')+fs.readFileSync(path.join(root,'scripts/js-cbor-text.js'),'utf8')+`;globalThis.refText=${text};globalThis.refHead=${head};globalThis.encoder=${encode};`,ctx,{timeout:10000});
function bytes(xs){const out=[];for(let x=xs;x.$!=='Nil';x=x.tail)out.push(x.head);return out;}
function same(s){const tail={$:'Con',head:19,tail:{$:'Nil'}},before=JSON.stringify(tail),want=bytes(ctx.refText(s,tail)),got=bytes(ctx.__bpCborText(s,tail,ctx.refHead));assert.deepEqual(got,want);assert.equal(JSON.stringify(tail),before);return got;}
test('all UTF-8 widths and raw lone-surrogate bytes equal compiled Enc.text',()=>{for(const s of ['','a','\u0000','\u007f','\u0080','\u07ff','\u0800','\uffff','é汉😀','\ud800','\udfff','x\ud800y','\udfff\ud800','\ud83d\ude00'])same(s);});
test('short/two/four-byte length heads are unchanged at UTF-8 byte boundaries',()=>{for(const n of [23,24,255,256,65535,65536])for(const ch of ['a','é','😀'])same(ch.repeat(n));});
test('deterministic mixed and malformed UTF-16 corpus equals compiled bytes',()=>{let seed=71;const pool=['a','é','汉','😀','\ud800','\udfff','\n','\u0000'];for(let i=0;i<128;i++){let s='';for(let k=0;k<i;k++){seed=(Math.imul(seed,1664525)+1013904223)>>>0;s+=pool[seed%pool.length];}same(s);}});
test('native text preserves the accumulator tail by identity without mutation',()=>{const tail={$:'Con',head:199,tail:{$:'Nil'}},got=ctx.__bpCborText('汉😀',tail,ctx.refHead);let x=got;for(let i=0;i<8;i++)x=x.tail;assert.equal(x,tail);assert.equal(tail.head,199);});
test('unchanged full encoder routes raw numbers, dictionary values/keys and nested fields through exact bytes',()=>{
 const end={$:'../core/json.End'},str=s=>({$:'../core/json.Str',text:s}),num=s=>({$:'../core/json.Num',raw:s}),values=[str('reply'),str('é\ud800😀'),num('4294967296'),num('-4294967295'),num('1.25'),{$:'../core/json.Flag',value:true},{$:'../core/json.Null'}];let items=end;for(const v of values.reverse())items={$:'../core/json.Item',head:v,tail:items};const j={$:'../core/json.Obj',fields:{$:'../core/json.Field',key:'result',value:{$:'../core/json.Arr',items},tail:{$:'../core/json.Field',key:'not-a-dictionary-key',value:str('汉'),tail:end}}};const before=bytes(ctx.encoder(j));vm.runInContext(`${text}=(s,acc)=>__bpCborText(s,acc,${head});`,ctx);assert.deepEqual(bytes(ctx.encoder(j)),before);
});
test('actual minified server transform lands once; web remains unchanged; missing/duplicate/head drift fail closed',()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'bp-cbor-primitive-'));
 try{const input=path.join(dir,'input.js'),min=path.join(dir,'min.js');fs.writeFileSync(input,source);cp.execFileSync('/home/h/.bun/bin/bun',['build','--minify-whitespace','--minify-syntax','--keep-names','--target=bun',input,'--outfile',min],{stdio:'pipe',timeout:20000});const original=fs.readFileSync(min,'utf8');
 const run=(s,server=true)=>{fs.writeFileSync(min,s);return cp.spawnSync('python3',[path.join(root,'scripts/js-native.py'),...(server?['--server']:[]),min],{encoding:'utf8',timeout:10000});};
 assert.equal(run(original).status,0);let got=fs.readFileSync(min,'utf8');assert.equal(got.split('return __bpCborText(').length-1,1);assert(got.includes(`return __bpCborText(_s_0,_acc_0,${head});`));const syntax=cp.spawnSync(process.execPath,['--input-type=module','--check'],{input:got,encoding:'utf8',timeout:10000});assert.equal(syntax.status,0,syntax.stderr.slice(0,200));
 assert.equal(run(original,false).status,0);assert(!fs.readFileSync(min,'utf8').includes('__bpCborText'));
 assert.notEqual(run(original.replace('function '+text+'(','function changedText(')).status,0);
 const start=original.indexOf('function '+text+'('),endAt=original.indexOf('function ',start+9),definition=original.slice(start,endAt);assert.notEqual(run(original+definition).status,0);
 assert.notEqual(run(original.replace('function '+head+'(','function changedHead(')).status,0);
 }finally{fs.rmSync(dir,{recursive:true,force:true});}
});
