const {test}=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),crypto=require('node:crypto');

test('parked resume preserves compiled continuation fingerprint without source or payload',()=>{
  const source=fs.readFileSync(path.resolve(__dirname,'../../src/server/effects/loop.js'),'utf8');
  const first=source.indexOf('function bp_wake()'),end=source.indexOf('async function bp_run(',first);
  const logs=[],runs=[],io={runs,waits:[],pend:0,wake:null};
  let clock=0;
  const ctx=vm.createContext({Date,performance:{now:()=>clock},process:{pid:7},require,console:{error:s=>logs.push(s)},
    BEND_IO:io,io_push:(fun,arg)=>runs.push({fun,arg})});
  vm.runInContext(source.slice(first,end)+'\nglobalThis.resume=bp_resume;globalThis.capture=bp_loop_slow;',ctx);
  const secret='PRIVATE_PROMPT_AUTH_URL';let calls=0;
  function continuation(x){calls++;return {$:'Chan.send',args:[null,x]};}
  continuation.j=function compiled(){return $server$058Hub$mcp$after$('PRIVATE_COMPILED_LITERAL');};
  ctx.resume(continuation,()=>secret);
  assert.equal(runs.length,1);const task=runs.shift(),op=task.fun(task.arg);
  assert.equal(calls,1);assert.equal(op.args[1],secret);
  ctx.capture(io,'dispatch','Chan.send',0,50000,{$:'Ready',value:{$:'Some',value:{$:'server.Rpc'}}},op,task.fun);
  const r=JSON.parse(logs[0].slice('[bp-loop] '.length));
  assert.equal(r.inputMessage,'Rpc');assert.equal(r.outputStringChars,secret.length);
  assert.equal(r.siteHash,crypto.createHash('sha256').update(continuation.j.toString()).digest('hex'));
  assert(r.sites.includes('hub.mcp.after'));assert(!logs.join('').includes('PRIVATE'));
  assert(!logs.join('').includes('$server$'));assert.equal(r.durationMs,50000);
  logs.length=0;
  ctx.resume(continuation,()=>{clock+=50000;return secret;});
  const reading=runs.shift();reading.fun(reading.arg);
  assert.equal(logs.length,1,'only the expensive native completion is attributed');
  assert.equal(JSON.parse(logs[0].slice('[bp-loop] '.length)).effect,'runtime.resume.more');
  logs.length=0;
  ctx.resume(x=>{clock+=50000;return continuation(x);},()=>secret);
  const computing=runs.shift();computing.fun(computing.arg);
  assert.equal(logs.length,1,'only the expensive compiled continuation is attributed');
  assert.equal(JSON.parse(logs[0].slice('[bp-loop] '.length)).effect,'runtime.resume.continuation');
  assert.equal(calls,3);assert(!logs.join('').includes('PRIVATE'));
});
