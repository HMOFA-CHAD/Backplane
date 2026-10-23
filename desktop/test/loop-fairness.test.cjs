const {test}=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),cp=require('node:child_process');
const file=path.resolve(__dirname,'../../src/server/effects/loop.js');
const current=fs.readFileSync(file,'utf8');
// The exact shipped scheduler, with its unbounded inner ready chain.
const original=cp.execFileSync('git',['show','3de9a9620:src/server/effects/loop.js'],{cwd:path.dirname(file),encoding:'utf8'});

async function run(source,{count=256,cost=1,park=-1}={}) {
  let clock=0,callbackAt=null,heartbeatAt=null,parked=false;
  const effects=[],logs=[];
  const ctx=vm.createContext({performance:{now:()=>clock},Date,Promise,setImmediate,setTimeout,clearTimeout,
    process:{pid:7,on(){},exit(){throw Error('unexpected runtime exit');}},console:{error:s=>logs.push(s)},
    $0eff:{},bp_base:()=>({}),bp_host:()=>({}),bp_file:()=>({}),io_park_on(){},
    io_errs:s=>{throw Error(s);},run_loop:value=>()=>value,
    io_push:(fun,arg,fresh)=>{ctx.BEND_IO.runs.push({fun,arg});ctx.BEND_IO.live+=fresh?1:0;},
  });
  const first=source.indexOf('function bp_wake()'),end=source.indexOf('// A program runs either from its emitted file',first);
  assert(first>=0&&end>first,'use actual scheduler functions');
  vm.runInContext(source.slice(first,end)+'\nglobalThis.run=bp_run;',ctx);
  function next(i){return i===count?{$:'Emit',value:null}:{$:'Step',args:[i,'PRIVATE_PROMPT_AUTH_URL'],kont:x=>next(x+1)};}
  ctx.$0eff.Step=(i,_private,k)=>{
    effects.push(i);clock+=cost;
    if(i===0)Promise.resolve().then(()=>{callbackAt=effects.length;});
    if(i===park&&!parked){parked=true;return ctx.io_park_promise(Promise.resolve(i),k,v=>v);}
    return i;
  };
  const rc=await ctx.run(()=>{
    ctx.BEND_IO.waits.push({at:10,more:()=>{heartbeatAt=effects.length;return undefined;}});
    return next(0);
  });
  return {rc,effects,callbackAt,heartbeatAt,logs,live:ctx.BEND_IO.live};
}

test('shipped scheduler starves callbacks and due heartbeat; ready-chain quantum fixes both',async()=>{
  const before=await run(original),after=await run(current);
  assert.equal(before.callbackAt,256,'control runs the entire chain before Bun can turn');
  assert.equal(before.heartbeatAt,null,'control never polls the due heartbeat inside this chain');
  assert(after.callbackAt<16,'native callback runs during the chain');
  assert(after.heartbeatAt>=10&&after.heartbeatAt<24,'due heartbeat runs during the chain');
  assert.equal(after.rc,0);assert.equal(after.live,0);
  assert.deepEqual(after.effects,Array.from({length:256},(_,i)=>i),'every effect executes once, in order');
});

test('an actually parked effect resumes once across quantum boundaries',async()=>{
  const r=await run(current,{park:7});
  assert.equal(r.rc,0);assert.equal(r.live,0);
  assert.deepEqual(r.effects,Array.from({length:256},(_,i)=>i));
});

test('slow-operation capture is bounded and excludes effect arguments and results',async()=>{
  const r=await run(current,{count:80,cost:1500});
  assert.equal(r.logs.length,64);assert(!r.logs.join('').includes('PRIVATE'));
  const records=r.logs.map(s=>JSON.parse(s.slice('[bp-loop] '.length)));
  assert(records.every(r=>r.phase==='effect'&&r.effect==='Step'&&r.durationMs===1500&&r.process===7));
  assert(records.every(r=>Object.keys(r).sort().join(',')==='at,durationMs,effect,pending,phase,process,runnable,waits'));
});
