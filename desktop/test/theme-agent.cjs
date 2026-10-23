// Deterministic Claude protocol stand-in for theme-stream.cjs, only for its
// private test home. A message naming THEME-ASK asks the hub for permission
// through Backplane's own MCP permission_prompt (as test/tools/runlife_e2e.ts
// does), so the ask is opened after the hub's start and stays open while the
// call waits; any other message streams like stream-agent.cjs (120 deltas,
// 50 ms apart, each naming its index and the stream's start).
const { createInterface } = require('node:readline');
const fs = require('node:fs');
const crypto = require('node:crypto');
if (process.argv.includes('--version')) { console.log('2.1.286'); process.exit(0); }
const session = `theme-fixture-${process.pid}`;
const emit = value => process.stdout.write(JSON.stringify({session_id:session,uuid:crypto.randomUUID(),...value})+'\n');
const delay = ms => new Promise(r=>setTimeout(r,ms));
const mcp = () => { const a = process.argv, i = a.indexOf('--mcp-config'); return JSON.parse(a[i+1]).mcpServers.backplane.url; };
let stopped = false;
createInterface({input:process.stdin}).on('line',async line=>{
  let user; try {user=JSON.parse(line);}catch{return;}
  if(user.type==='control_request'&&user.request?.subtype==='interrupt'){stopped=true;return;}
  if(user.type!=='user')return;
  const text=typeof user.message?.content==='string'?user.message.content:(user.message?.content??[]).map(b=>b.text??'').join(' ');
  emit({type:'system',subtype:'init',tools:[],mcp_servers:[],model:'sonnet',claude_code_version:'2.1.286',capabilities:['msg_lifecycle_v1']});
  emit({type:'command_lifecycle',command_uuid:user.uuid,state:'started'});
  if(text.includes('THEME-ASK')){
    // answered (or the turn stopped) when the call returns
    await fetch(mcp(),{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({jsonrpc:'2.0',id:1,method:'tools/call',
      params:{name:'permission_prompt',arguments:{tool_name:'Read',input:{file_path:'board.kicad_pcb'},tool_use_id:'theme-fixture-ask'}}})}).catch(()=>{});
    emit({type:'result',subtype:'success',is_error:false,num_turns:1,result:'asked',usage:{}});
    emit({type:'command_lifecycle',command_uuid:user.uuid,state:'completed'});
    return;
  }
  stopped=false;
  emit({type:'stream_event',event:{type:'message_start',message:{id:'stream-'+process.pid,role:'assistant',content:[],usage:{input_tokens:10}}}});
  emit({type:'stream_event',event:{type:'content_block_start',index:0,content_block:{type:'text',text:''}}});
  let full='';const start=Date.now();
  for(let i=0;i<120&&!stopped;i++){
    const part=`sample-${i}(${start}) The board and the reply stay responsive. `;full+=part;
    if(process.env.BP_AGENT_TRACE)fs.appendFileSync(process.env.BP_AGENT_TRACE,JSON.stringify({sample:i,ms:Date.now()})+'\n');
    emit({type:'stream_event',event:{type:'content_block_delta',index:0,delta:{type:'text_delta',text:part}}});
    await delay(50);
  }
  emit({type:'stream_event',event:{type:'content_block_stop',index:0}});
  emit({type:'assistant',message:{id:'stream-'+process.pid,role:'assistant',content:[{type:'text',text:full}]},parent_tool_use_id:null});
  emit({type:'result',subtype:'success',is_error:false,num_turns:1,result:full,usage:{}});
  emit({type:'command_lifecycle',command_uuid:user.uuid,state:stopped?'cancelled':'completed'});
});
const parent=process.ppid;
setInterval(()=>{try {process.kill(parent,0);}catch{process.exit(0);}},1000).unref();
