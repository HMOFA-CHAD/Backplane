'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const tag='a'.repeat(64),context={kind:'mail-draft',owner:'bot-A',origin:'actual-epoch',conv:'conv-A',recipient:'Room'};
async function fixture(){
 const {ThinMailDraft,mailDraftContext,mailReplyField}=await import('../../src/web/mail-drafts.js');
 let credential=tag,ui={context:null,text:'',online:true,state:'CURRENT',outbox:'UNCHANGED'};const storage=new Map(),reads=[],writes=[];
 const api={identity:()=>credential,context:c=>{ui={...ui,context:c};},key:()=>ui.context?'legacy:'+JSON.stringify([ui.context.origin,ui.context.owner,ui.context.conv]):'',field:text=>{ui={...ui,text};},snapshot:()=>JSON.stringify({draft:ui.text,state:'sending',text:'old captured',to:'secret recipient',previous:'old id',error:'old error'}),restoreText:s=>JSON.parse(s).draft||'',read:key=>{reads.push(key);return storage.get(key);},write:(key,value)=>{writes.push({key,value});storage.set(key,value);}};
 const draft=new ThinMailDraft(api);return{draft,api,storage,reads,writes,mailDraftContext,mailReplyField,ui:()=>ui,setCredential:s=>credential=s};
}
test('mail draft: exact current context and epoch required; malformed or missing context clears local identity',async()=>{
 const f=await fixture();for(const c of [null,{...context,origin:'foreign'},{...context,owner:''},{...context,token:'extra'}]){assert.equal(f.mailDraftContext(c,'actual-epoch'),null);f.draft.bind(c,'actual-epoch','current');assert.equal(f.ui().context,null);assert.equal(f.writes.length,0);}
 f.draft.bind(context,'actual-epoch','current');assert.equal(f.ui().text,'current');assert.equal(f.ui().online,true);assert.equal(f.ui().state,'CURRENT');assert.equal(f.ui().outbox,'UNCHANGED');
});
test('mail draft: persistence is credential partitioned and writes only the existing policy draft text',async()=>{
 const f=await fixture();f.storage.set('backplane-mail:legacy:'+JSON.stringify([context.origin,context.owner,context.conv]),JSON.stringify({draft:'old unpartitioned'}));f.draft.bind(context,'actual-epoch','actual');
 assert.equal(f.ui().text,'actual');assert(f.reads.every(k=>k.startsWith('backplane-mail-v2:')&&k.includes(tag)));assert.deepEqual(JSON.parse(f.writes.at(-1).value),{draft:'actual'});
 f.draft.edit('日本語 👩‍💻 é\n');assert.deepEqual(JSON.parse(f.writes.at(-1).value),{draft:'日本語 👩‍💻 é\n'});
});
test('mail draft: missing credential tag allows current local editing but no storage reads or writes',async()=>{
 const f=await fixture();f.setCredential('');f.draft.bind(context,'actual-epoch','live');f.draft.edit('local');f.draft.checkpoint();assert.equal(f.ui().text,'local');assert.equal(f.reads.length,0);assert.equal(f.writes.length,0);
});
test('mail draft: restore is only local text and never becomes an action or restored outbox authority',async()=>{
 const f=await fixture();f.draft.bind(context,'actual-epoch','');const key=f.writes.at(-1).key;f.storage.set(key,JSON.stringify({draft:'restored 日本語',state:'sending',text:'old send'}));
 f.draft.clear();f.storage.set(key,JSON.stringify({draft:'restored 日本語',state:'sending',text:'old send'}));f.draft.bind(context,'actual-epoch','');assert.equal(f.ui().text,'restored 日本語');assert.equal(f.draft.needsSubmit(),true);assert.equal(f.draft.fieldValue('mrreply',''),'restored 日本語');assert.equal(f.draft.fieldValue('password','server'),'server');assert.equal(f.ui().outbox,'UNCHANGED');
 f.draft.bind(context,'actual-epoch','');assert.equal(f.ui().text,'restored 日本語');assert.equal(f.draft.needsSubmit(),true);
});
test('mail draft: actual accepted value wins over saved text and later filed value clears only the accepted field',async()=>{
 const f=await fixture();f.draft.bind(context,'actual-epoch','');const key=f.writes.at(-1).key;f.draft.clear();f.storage.set(key,JSON.stringify({draft:'old saved'}));f.draft.bind(context,'actual-epoch','accepted current');assert.equal(f.ui().text,'accepted current');assert.equal(f.draft.needsSubmit(),false);
 f.draft.edit('newer edit');f.draft.bind(context,'actual-epoch','newer edit');assert.equal(f.ui().text,'newer edit');f.draft.bind(context,'actual-epoch','');assert.equal(f.ui().text,'');assert.deepEqual(JSON.parse(f.writes.at(-1).value),{draft:''});
});
test('mail draft: deliberate empty survives persistence and is not replaced by an older local snapshot',async()=>{
 const f=await fixture();f.draft.bind(context,'actual-epoch','live');f.draft.edit('');f.draft.bind(context,'actual-epoch','');assert.equal(f.ui().text,'');assert.equal(JSON.parse(f.writes.at(-1).value).draft,'');
});
test('mail draft: credential rotation cannot write an old draft under the new tag or read its old partition',async()=>{
 const f=await fixture();f.draft.bind(context,'actual-epoch','first credential');const before=f.writes.length;f.setCredential('b'.repeat(64));f.draft.checkpoint();assert.equal(f.writes.length,before);assert.equal(f.draft.matches(context,'actual-epoch'),false);f.draft.bind(context,'actual-epoch','');assert.equal(f.ui().text,'');assert(f.writes.at(-1).key.includes('b'.repeat(64)));assert(f.reads.at(-1).includes('b'.repeat(64)));
});
test('mail draft: owner/conversation changes isolate both draft overlay and pending send scopes',async()=>{
 const f=await fixture();f.draft.bind(context,'actual-epoch','A');const first=f.draft.scope(),send=f.draft.scope(true);f.draft.bind({...context,recipient:'bot-B'},'actual-epoch','A');assert.equal(f.draft.scope(),first);assert.notEqual(f.draft.scope(true),send);f.draft.bind({...context,conv:'conv-B'},'actual-epoch','B');assert.notEqual(f.draft.scope(),first);assert.equal(f.ui().text,'B');
});
test('mail draft: corrupt storage and write failures leave current live text available',async()=>{
 const f=await fixture();f.api.read=()=>'{bad';f.api.write=()=>{throw Error('quota');};f.draft.bind(context,'actual-epoch','');f.draft.edit('current local');assert.equal(f.ui().text,'current local');
});
test('mail draft: reply text comes only from the exact single normal textarea field',async()=>{
 const f=await fixture(),node=text=>({type:'element',tag:'textarea',attrs:[{name:'data-bfield',value:'mrreply'},{name:'value',value:text}],kids:[]});
 assert.equal(f.mailReplyField(node('日本語')),'日本語');assert.equal(f.mailReplyField({type:'element',tag:'div',attrs:[],kids:[node('a'),node('b')]}),undefined);assert.equal(f.mailReplyField({type:'text',text:'not a field'}),undefined);
});
