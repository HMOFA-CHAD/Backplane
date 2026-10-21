import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
const lib=(await import(pathToFileURL(process.argv[2]).href)).default;
function children(xs){const out=[];for(;xs?.$==='Con';xs=xs.tail)out.push(xs.head);return out;}
function nodes(root){const out=[],todo=[root];while(todo.length){const n=todo.pop();out.push(n);todo.push(...children(n.kids));}return out;}
function attr(node,key){return children(node.attrs).find(a=>a.name===key)?.value;}
function text(node){return node?.text??children(node?.kids).map(text).join('');}
function snapshot(index){const ns=nodes(lib.scenario(BigInt(index)));return{bodies:ns.filter(n=>attr(n,'class')==='mail-text').map(text).sort(),targets:ns.filter(n=>children(n.attrs).some(a=>a.event==='click'&&a.action==='mail-to')).map(n=>attr(n,'data-value')).sort(),error:text(ns.find(n=>n.key==='mail-error')),errorRole:attr(ns.find(n=>n.key==='mail-error'),'role'),readHint:text(ns.find(n=>n.key==='mail-read-status'))};}
let checks=0;function check(name,actual,expected){assert.deepEqual(actual,expected,name);console.log('ok '+name);checks++;}
const pending=snapshot(0);check('B before RPC has no cached A body',pending.bodies,[]);check('B before RPC has no cached A recipient',pending.targets,[]);check('B before RPC renders loading',pending.readHint,'Loading message bodies…');
for(const [index,label]of [[1,'A success then B failure'],[2,'B failure then A success'],[5,'B failure then stale A error'],[6,'stale A error then B failure']]){
 const s=snapshot(index);check(label+' has no A body under B',s.bodies,[]);check(label+' has no A recipient under B',s.targets,[]);check(label+' preserves exact B error',s.error,'B body unavailable');check(label+' exposes actual alert role',s.errorRole,'alert');check(label+' renders read-failure hint',s.readHint,'Messages could not be loaded. See the mail error above.');
}
for(const [index,label]of [[3,'cached B refresh failure'],[7,'cached B pending refresh']]){
 const s=snapshot(index);check(label+' retains only B body',s.bodies,['B cached body']);check(label+' retains only B/member/Room recipients',s.targets,['bot:bub','bot:member-b','room:B']);check(label+' does not replace cached text with empty hint',s.readHint,'');if(index===3)check(label+' retains backend error alert',s.error,'B body unavailable');
}
const a=snapshot(4);check('reopen A restores its exact cached bodies',a.bodies,['A cached body','A late body']);check('reopen A restores its own recipients',a.targets,['bot:bub','bot:member-a','room:A']);check('B error does not leak into reopened A',a.error,'');
console.log(JSON.stringify({pass:true,checks,scope:'exact composed client + production MA.recv/WM.page transition controls only; no old25 replay, RPC execution, service/native build, live data or GUI'}));
