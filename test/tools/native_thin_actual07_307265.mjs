// Actual emitted bundle + sanitized actual318417 ordered frame regression.
// No native UI, service execution, installation or startup-timing acceptance.
import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
import {cbor,plain} from '../../src/web/wire.js';
const [bundlePath,fixturePath='test/fixtures/native-thin-actual07-307265.json']=process.argv.slice(2);
assert(bundlePath,'actual qualified emitted bundle path required');
const fixture=JSON.parse(fs.readFileSync(fixturePath,'utf8')),source=fs.readFileSync(bundlePath,'utf8');
const ctx=vm.createContext({Date,console});vm.runInContext(source,ctx,{timeout:10000});
const call=(m,...a)=>{ctx.__bp_method=m;ctx.__bp_args=a;return vm.runInContext('Backplane[__bp_method](...__bp_args)',ctx,{timeout:10000});};
const out=(m,...a)=>JSON.parse(call(m,...a));const dictionaries=JSON.parse(call('headerKeys'));
const head=(m,n)=>n<24?Buffer.from([(m<<5)|n]):n<256?Buffer.from([(m<<5)|24,n]):n<65536?Buffer.from([(m<<5)|25,n>>8,n&255]):Buffer.from([(m<<5)|26,n>>>24,(n>>>16)&255,(n>>>8)&255,n&255]);
const encode=v=>v===null?Buffer.from([246]):typeof v==='boolean'?Buffer.from([v?245:244]):typeof v==='number'?(v>4294967295?Buffer.concat([Buffer.from([199]),encode(String(v))]):head(0,v)):typeof v==='string'?Buffer.concat([head(3,Buffer.byteLength(v)),Buffer.from(v)]):Array.isArray(v)?Buffer.concat([head(4,v.length),...v.map(encode)]):Buffer.concat([head(5,Object.keys(v).length),...Object.entries(v).flatMap(([k,x])=>[encode(k),encode(x)])]);
const requests=o=>o.cmds.filter(x=>x.type==='send').map(x=>plain(cbor(new Uint8Array(Buffer.from(x.data,'base64')),dictionaries.keys,dictionaries.words)));
const hub=fixture.reply.result.hub,thread=fixture.reply.result.target.id,recv=v=>out('recv',hub,encode(v).toString('base64'),'1',false,false);
let checks=0;const check=(ok,msg)=>{assert(ok,msg);checks++;};
call('start','sanitized-actual07-replay',JSON.stringify({[hub+'|'+thread]:'local-draft-fixture'}));
call('hubs',[hub]);call('local','mailroom-renderer','ios-v1');call('connection',hub,'1','view-v1');call('act','select',hub+'|'+thread);
const greeting=recv(fixture.greeting),open=requests(greeting)[0];check(open?.m==='view.open','one bounded selected open');
check(greeting.sync.length===1&&greeting.sync[0].phase==='presenting','native observes exact presentation fence');
const deadline=greeting.deadline,compact=call('savePresentation');
for(const frame of fixture.before){const x=recv(frame);check(x.inert===true&&x.screen===null&&x.sync.length===0&&x.cmds.length===0,'actual07 pre-reply info is inert, not failed');check(x.deadline===deadline&&call('savePresentation')===compact,'actual07 pre-reply retains pending deadline and choices');}
// hb is source-established, not falsely claimed observed in actual07.
const heartbeat=recv({t:'hb'});check(heartbeat.inert===true&&heartbeat.deadline===deadline,'source-established heartbeat also preserves request');
const response=structuredClone(fixture.reply);response.id=open.id;response.result.requestRevision=open.p.requestRevision;
const shown=recv(response);check(shown.sync.length===1&&shown.sync[0].phase==='presented','actual07 reply satisfies still-active native fence');
check(shown.screen?.thread?.entries.length===32&&shown.screen.thread.earlier===24032,'actual bounded long-history presentation preserved');
check(shown.screen?.thread?.id===hub+'|'+thread,'exact current owner');check(requests(shown).length===0,'no automatic history or page');
for(const frame of fixture.after){const x=recv(frame);check(x.inert===true&&x.screen===null&&x.sync.length===0&&x.cmds.length===0,'actual07 post-reply info cannot retire readiness');}
const read=out('reading',hub+'|'+thread,'tail-63',32,true);check(requests(read).length===0,'reading position never requests older history');
const page=out('act','earlier',''),sent=requests(page);check(sent.length===1&&sent[0].m==='view.page','next explicit gesture issues exactly one page');
check(sent[0].p.cursor===response.result.window.older,'page uses exact current server cursor');
check(page.sync.length===1&&page.sync[0].phase==='presenting'&&page.sync[0].requestRevision>open.p.requestRevision,'page has a newer strict presentation fence');
check(!sent.some(x=>['mobile.history','frontend.history','turn.start'].includes(x.m)),'no canonical download or resend');
console.log(JSON.stringify({pass:true,checks,scope:'Actual emitted bridge + sanitized captured07 long-history envelopes. No native/service/UI runtime acceptance.'}));
