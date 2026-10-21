import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
const lib=(await import(pathToFileURL(process.argv[2]).href)).default;
let checked=0;
function check(name,actual,expected){assert.deepEqual(actual,expected,name);console.log('ok '+name);checked++;}
for(const to of ['room:opaque|fixture','bot:bub']){
 check(to+' committed OFF reports paused',lib.status(to,'off','filed'),'Filed; automation paused');
 check(to+' committed ON reports filed',lib.status(to,'on','filed'),'Filed');
}
for(const to of ['thread:fixture','person'])check(to+' does not imply automation route',lib.status(to,'off','filed'),'Filed');
for(const [state,text]of [['ack','Acknowledged; waiting for committed message'],['sending','Sending; draft preserved'],['unknown','Outcome unknown; check the conversation before sending again. Draft preserved.']])check('room '+state+' does not imply committed filing',lib.status('room:opaque|fixture','off',state),text);
function opts(choice){const out=[];for(let xs=lib.targets(choice);xs.$==='Con';xs=xs.tail){const n=xs.head,attrs=[];for(let as=n.attrs;as.$==='Con';as=as.tail)attrs.push(as.head);out.push({label:n.kids.head.text,value:attrs.find(a=>a.name==='data-value')?.value,action:attrs.find(a=>a.event==='click')?.action,on:attrs.find(a=>a.name==='class')?.value.includes('on')});}return out;}
check('canonical Room option renders exact opaque target without auto selection',opts(''),[{label:'Member',value:'bot:member',action:'mail-to',on:false},{label:'Room',value:'room:opaque|fixture',action:'mail-to',on:false}]);
check('existing member choice is preserved when Room option is present',opts('bot:member').map(o=>o.on),[true,false]);
check('explicit Room selection renders only that option selected',opts('room:opaque|fixture').map(o=>o.on),[false,true]);
console.log(JSON.stringify({pass:true,checks:checked,scope:'changed production room status and target nodes only; no sends, old25 replay, service/native build or GUI'}));
