import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
const lib=(await import(pathToFileURL(process.argv[2]).href)).default;
const list=xs=>xs.reduceRight((tail,head)=>({$:'Con',head,tail}),{$:'Nil'});
let checked=0;
function check(name,actual,expected){assert.deepEqual(actual,expected,name);console.log('ok '+name);checked++;}
check('receiver prefers owner after another bot',lib.preferred(list(['bot:first','bot:owner']),'owner'),'owner');
check('receiver prefers owner after person and multiple bots',lib.preferred(list(['person','bot:first','thread:other','bot:owner']),'owner'),'owner');
check('receiver falls back first bot when owner is absent',lib.preferred(list(['person','thread:other','bot:first','bot:second']),'owner'),'first');
check('receiver remains empty without any bot participant',lib.preferred(list(['person','thread:other']),'owner'),'');
check('receiver remains empty for no participants',lib.preferred(list([]),'owner'),'');
for(const loading of [false,true])for(const failed of [false,true]){
 check('existing bodies stay visible '+JSON.stringify({loading,failed}),lib.hint(loading,failed,true),'');
 check('missing body state '+JSON.stringify({loading,failed}),lib.hint(loading,failed,false),loading?'Loading message bodies…':failed?'Messages could not be loaded. See the mail error above.':'No message bodies were returned for this conversation.');
}
function flatten(root){const nodes=[],todo=[root];while(todo.length){const node=todo.pop();nodes.push(node);for(let kids=node.kids;kids?.$==='Con';kids=kids.tail)todo.push(kids.head);}return nodes;}
const nodes=flatten(lib.reader());
const status=nodes.find(node=>node.key==='mail-read-status');assert(status,'production reader contains status');
let attrs=[];for(let xs=status.attrs;xs?.$==='Con';xs=xs.tail)attrs.push(xs.head);
check('production reader exposes polite status',attrs.filter(a=>a.name==='role'||a.name==='aria-live').map(a=>[a.name,a.value]),[['role','status'],['aria-live','polite']]);
check('production reader renders truthful no-body text',status.kids.head.text,'No message bodies were returned for this conversation.');
const text=(node,key)=>flatten(node).find(node=>node.key===key)?.kids.head.text;
let pending=lib.pending('Previous send failed');
check('actual pending state renders loading',text(lib.reader_from(pending),'mail-read-status'),'Loading message bodies…');
const requestId=lib.read_id(pending);
const empty=lib.respond(pending,requestId,true,'');
check('successful empty read is not mislabelled by prior send error',text(lib.reader_from(empty),'mail-read-status'),'No message bodies were returned for this conversation.');
check('prior send error remains visible separately',text(lib.page(empty),'mail-error'),'Previous send failed');
const failed=lib.respond(pending,requestId,false,'Body store unavailable');
check('actual correlated read failure renders failure status',text(lib.reader_from(failed),'mail-read-status'),'Messages could not be loaded. See the mail error above.');
check('actual backend error remains visible',text(lib.page(failed),'mail-error'),'Body store unavailable · Previous send failed');
pending=lib.request_again(failed);
const recovered=lib.respond(pending,lib.read_id(pending),true,'');
check('successful retry clears only read failure',text(lib.page(recovered),'mail-error'),'Previous send failed');
check('successful retry empty result remains truthful',text(lib.reader_from(recovered),'mail-read-status'),'No message bodies were returned for this conversation.');
const newer=lib.request_again(lib.pending(''));
const stale=lib.respond(newer,requestId,false,'Stale read failure');
check('old read response cannot fail current pending read',text(lib.reader_from(stale),'mail-read-status'),'Loading message bodies…');
check('old read failure is not attached to current conversation',text(lib.page(stale),'mail-error'),'');
const foreign=lib.respond(lib.other_conversation(lib.pending('')),requestId,false,'Other conversation failure');
check('different conversation does not inherit read error',text(lib.page(foreign),'mail-error'),'');
console.log(JSON.stringify({pass:true,checks:checked,scope:'emitted production receiver and reader nodes only; no service, DOM runtime, live action or mailbox send'}));
