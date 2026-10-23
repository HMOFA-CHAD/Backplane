// Exact emitted Context.read, isolated synthetic history, native timer fairness.
// No service launch, profile access, user payload, build or UI navigation.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const {performance}=require('node:perf_hooks');
const [candidate,baseline,out]=process.argv.slice(2);
if(!candidate||!baseline||!out)throw Error('candidate all.js, baseline all.js and receipt required');
function compiled(file){
  const source=fs.readFileSync(file,'utf8'),defs=new Map();
  for(const m of source.matchAll(/^function ([\w$]+)\([^\n]*\) \{[\s\S]*?^\}/gm))defs.set(m[1],m[0]);
  const root=[...defs.keys()].find(x=>x.endsWith('mailcontext$058Context$read$'));
  assert(root,'use the actual emitted history reader');
  const wanted=new Set();function visit(name){if(wanted.has(name))return;wanted.add(name);
    for(const m of defs.get(name).matchAll(/[A-Za-z_$][\w$]*/g))if(defs.has(m[0])&&!wanted.has(m[0]))visit(m[0]);}
  visit(root);const ctx=vm.createContext({});
  vm.runInContext([...wanted].map(x=>defs.get(x)).join('\n')+'\nglobalThis.read='+root+';',ctx,{timeout:5000});
  return ctx;
}
function list(xs){let tail={$:'Nil'};for(let i=xs.length-1;i>=0;i--)tail={$:'Con',head:xs[i],tail};return tail;}
function line(owner,id,text){return JSON.stringify({$: 'MessagePosted',thread:owner,msg:id,role:'user',text,at:1});}
const noise=Array.from({length:1920},(_,i)=>line('other','private-'+i,'UNRELATED_PRIVATE_BODY '.repeat(48)));
const lines=list([...noise,line('owner','new','Hardware newest'),line('owner','middle','Hardware middle'),line('owner','old','Hardware oldest')]);
async function run(file){
  const ctx=compiled(file),began=performance.now();let ticks=0,last=began,maxTickGapMs=0,maxSynchronousMs=0,sleeps=0;
  const pulse=setInterval(()=>{const now=performance.now();maxTickGapMs=Math.max(maxTickGapMs,now-last);last=now;ticks++;},1);
  ctx.args={$:'../core/json.Obj',fields:{$:'../core/json.End'}};ctx.lines=lines;
  ctx.finish=value=>({$:'Emit',value});
  const evaluate=expression=>{const t=performance.now();try{return vm.runInContext(expression,ctx,{timeout:5000});}finally{maxSynchronousMs=Math.max(maxSynchronousMs,performance.now()-t);}};
  try{
    let op=evaluate('run_loop(read(true,"","owner",args,lines)(finish))');
    while(op?.$!=='Emit'){
      assert.equal(op?.$,'IO.sleep','fallback must only yield, never query a database or perform another effect');
      assert.equal(op.args[0],0);sleeps++;
      await new Promise(resolve=>setTimeout(resolve,0));
      ctx.kont=op.kont;ctx.unit={$:'Unit'};op=evaluate('run_loop(kont(unit))');
    }
    return {file,ms:performance.now()-began,ticks,sleeps,maxTickGapMs,maxSynchronousMs,value:op.value};
  }finally{clearInterval(pulse);}
}
(async()=>{
  const before=await run(baseline),after=await run(candidate);
  assert.equal(JSON.stringify(after.value),JSON.stringify(before.value),'same whole owner history and global sequence cursor');
  assert.equal(before.ticks,0,'control blocks native callbacks until its whole scan is complete');
  assert.equal(before.sleeps,0);
  assert(after.sleeps>=32,'candidate yields throughout the sparse global history');
  assert(after.ticks>0,'native timers run before the scan completes');
  assert(after.maxSynchronousMs<1000,'bounded synthetic scan leaves no second-long synchronous segment');
  const clean=r=>{const {value,...metadata}=r;return metadata;};
  const receipt={state:'passed',engine:process.versions.bun?'Bun':'Node',syntheticWireLines:1923,before:clean(before),after:clean(after),
    scope:'actual emitted history reader with synthetic unrelated history; same results and timers during scan',
    limit:'No user-profile/UI replay; not a claim that every possible server stall is eliminated'};
  fs.writeFileSync(out,JSON.stringify(receipt,null,2)+'\n',{mode:0o600});console.log(JSON.stringify(receipt));
})().catch(error=>{console.error(error.message);process.exitCode=1;});
