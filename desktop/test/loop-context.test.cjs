const {test}=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');

test('slow dispatch identifies only fixed message kinds, excluding channel payloads',()=>{
  const source=fs.readFileSync(path.resolve(__dirname,'../../src/server/effects/loop.js'),'utf8');
  const first=source.indexOf('let bp_loop_slow_count = 0;'),end=source.indexOf('async function bp_run(',first);
  const logs=[],ctx=vm.createContext({Date,process:{pid:7},console:{error:s=>logs.push(s)}});
  vm.runInContext(source.slice(first,end)+'\nglobalThis.capture=bp_loop_slow;',ctx);
  const io={runs:[],waits:[],pend:0},secret='PRIVATE_AUTH_URL_PROMPT';
  ctx.capture(io,'dispatch','Chan.send',0,50000,
    {$:'Some',value:{$:'server.Bulk',m:{$:'server.Rpc',text:secret}}},
    {$:'Chan.send',args:[{secret},{$:'server.AgentLine',thread:secret,line:secret}]});
  ctx.capture(io,'dispatch','Chan.send',0,50000,
    {$:'Some',value:{$:'server.'+secret}},{$:'Chan.send',args:[null,{$:secret,text:secret}]});
  const records=logs.map(s=>JSON.parse(s.slice('[bp-loop] '.length)));
  assert.equal(records[0].inputMessage,'Rpc');assert.equal(records[0].outputMessage,'AgentLine');
  assert(!('inputMessage' in records[1]));assert(!('outputMessage' in records[1]));
  assert(!logs.join('').includes(secret));
  assert.equal(records[0].durationMs,50000);
});
