// Deterministic Claude protocol stand-in, only for the private test home.
const { createInterface } = require('node:readline');
const fs = require('node:fs');
const crypto = require('node:crypto');
if (process.argv.includes('--version')) { console.log('2.1.286'); process.exit(0); }
const session = `electron-smoke-${process.pid}`;
const emit = value => process.stdout.write(JSON.stringify({session_id:session,uuid:crypto.randomUUID(),...value})+'\n');
const delay = ms => new Promise(r=>setTimeout(r,ms));
createInterface({input:process.stdin}).on('line',async line=>{
  let user; try {user=JSON.parse(line);}catch{return;}
  if(user.type!=='user')return;
  emit({type:'system',subtype:'init',tools:[],mcp_servers:[],model:'sonnet',claude_code_version:'2.1.286',capabilities:['msg_lifecycle_v1']});
  emit({type:'command_lifecycle',command_uuid:user.uuid,state:'started'});
  emit({type:'stream_event',event:{type:'message_start',message:{id:'stream-'+process.pid,role:'assistant',content:[],usage:{input_tokens:10}}}});
  emit({type:'stream_event',event:{type:'content_block_start',index:0,content_block:{type:'text',text:''}}});
  let full='';
  for(let i=0;i<120;i++){
    const text=`sample-${i}(${Date.now()}) The board and the reply stay responsive. `; full+=text;
    fs.appendFileSync(process.env.BP_AGENT_TRACE,JSON.stringify({sample:i,ms:Date.now()})+'\n');
    emit({type:'stream_event',event:{type:'content_block_delta',index:0,delta:{type:'text_delta',text}}});
    await delay(50);
  }
  emit({type:'stream_event',event:{type:'content_block_stop',index:0}});
  emit({type:'assistant',message:{id:'stream-'+process.pid,role:'assistant',content:[{type:'text',text:full}]},parent_tool_use_id:null});
  emit({type:'result',subtype:'success',is_error:false,num_turns:1,result:full,usage:{}});
  emit({type:'command_lifecycle',command_uuid:user.uuid,state:'completed'});
});
const parent=process.ppid;
setInterval(()=>{try {process.kill(parent,0);}catch{process.exit(0);}},1000).unref();
