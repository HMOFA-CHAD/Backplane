'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../../scripts/js-stack-prelude.js'),'utf8');
function boot({marker,soft=8n<<20n,hard=4n<<30n,jsc='4000000000',pid=200,argv='/$bunfs/root/backplane-serve',platform='linux',failRaise=false}={}){
 const calls={raise:[],exec:0},env={};if(marker!==undefined)env.BACKPLANE_STACK_SET=marker;if(jsc!==undefined)env.BUN_JSC_maxPerThreadStackUsage=jsc;
 const proc={pid,platform,env,argv:['bun',argv,'--plot','0','/fixture/board.kicad_pcb'],execPath:'/fixture/backplane-serve'};
 const ffi={ptr:x=>x,dlopen:()=>({symbols:{getrlimit:(_r,lim)=>{lim[0]=soft;lim[1]=hard;return 0},setrlimit:(_r,lim)=>{calls.raise.push([...lim]);return failRaise?-1:0},execve:(_file,args,envs)=>{calls.exec++;return -1}}})};
 // Pointers need only distinct numeric addresses for the argv/env vectors.
 let address=1n;ffi.ptr=x=>x instanceof BigUint64Array?x:address++;
 vm.runInNewContext(source,{process:proc,Buffer,BigUint64Array,require:n=>{assert.equal(n,'bun:ffi');return ffi}});
 return {calls,env};
}
test('a plot child with its parent marker raises its lowered stack and re-execs',()=>{
 const r=boot({marker:'100'});assert.deepEqual(r.calls.raise,[[4n<<30n,4n<<30n]]);assert.equal(r.calls.exec,1);assert.equal(r.env.BACKPLANE_STACK_SET,'200');
});
test('the legacy inherited marker also cannot suppress child setup',()=>{
 const r=boot({marker:'1'});assert.equal(r.calls.exec,1);assert.equal(r.calls.raise.length,1);
});
test('the same PID after exec skips setup, preventing an exec loop',()=>{
 const r=boot({marker:'200'});assert.equal(r.calls.exec,0);assert.equal(r.calls.raise.length,0);
});
test('an already sufficient inherited stack needs no exec',()=>{
 const r=boot({marker:'100',soft:4n<<30n});assert.equal(r.calls.exec,0);assert.equal(r.calls.raise.length,0);
});
test('a constrained hard stack limit is respected',()=>{
 const r=boot({marker:'100',hard:64n<<20n});assert.deepEqual(r.calls.raise,[[64n<<20n,64n<<20n]]);assert.equal(r.calls.exec,1);
});
test('failed setup continues without an exec loop; uncompiled and other platforms are untouched',()=>{
 assert.equal(boot({marker:'100',failRaise:true}).calls.exec,0);
 assert.equal(boot({argv:'/fixture/program.js'}).calls.exec,0);
 assert.equal(boot({platform:'win32'}).calls.exec,0);
});
