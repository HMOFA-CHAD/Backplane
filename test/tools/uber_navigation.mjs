import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
const lib=(await import(pathToFileURL(process.argv[2]).href)).default;
const tag=x=>x?.$?.split('.').at(-1);
const array=xs=>{const out=[];for(;tag(xs)==='Con';xs=xs.tail)out.push(xs.head);return out};
const json=j=>{switch(tag(j)){case 'Str':return j.text;case 'Num':return Number(j.raw);case 'Flag':return j.value;case 'Null':return null;case 'Arr':{const r=[];for(let f=j.items;tag(f)==='Item';f=f.tail)r.push(json(f.head));return r;}case 'Obj':{const r={};for(let f=j.fields;tag(f)==='Field';f=f.tail)r[f.key]=json(f.value);return r;}default:throw Error(JSON.stringify(j));}};
let count=0;
const check=(name,got,want)=>{assert.deepEqual(got,want,name);count++;console.log('ok '+name)};
const flatten=root=>{const out=[],todo=[root];while(todo.length){const n=todo.pop();out.push(n);todo.push(...array(n.kids).reverse());}return out};
const attrs=n=>Object.fromEntries(array(n.attrs).filter(a=>tag(a)==='At').map(a=>[a.name,a.value]));
const buttons=n=>flatten(n).filter(n=>n.tag==='button').map(n=>attrs(n));
const expected=['chat','mail','space','browser','memory','routines','settings'];
const parents={status:'mail',tasks:'browser',hooks:'settings'};
for(const [route,parent] of Object.entries(parents)){
 const p=json(lib.phone(route));
 check(route+' exact route',p.tab,route);
 check(route+' parent',p.navTab,parent);
 check(route+' exact bar',p.tabs.map(t=>t.id),expected);
 check(route+' nested sections',p.subtabs.map(t=>t.id),[parent,route]);
 check(route+' actual click preserves route',lib.click(route),route);
 check(route+' web parent highlight',lib.nav(lib.navbar(route),true),parent+';');
 const nodes=flatten(lib.panel(route));
 const sections=nodes.find(n=>n.key==='bot-subtabs');
 check(route+' web nested route buttons',buttons(sections).map(b=>b['data-value']),[parent,route]);
 check(route+' selected body remains exact',nodes.some(n=>n.key==='bot-body:'+route),true);
}

for(const route of expected){
 const p=json(lib.phone(route));
 check(route+' phone selection',p.tab,route);
 check(route+' web bar',buttons(lib.navbar(route)).map(b=>b['data-value']),expected);
}
check('phone hooks content preserved',json(lib.phone('hooks')).hooks[0].id,'h');
check('phone settings content preserved',json(lib.phone('settings')).settings.persona,'hello');
check('phone memory content preserved',json(lib.phone('memory')).memory[0].text,'green');
check('phone mail parent has actual Mailroom payload',typeof json(lib.phone('mail')).mailroom,'object');
check('default selection opens Chat',lib.click(''),'chat');
check('unknown selection falls back to Chat',lib.click('unknown'),'chat');
check('remote bot tabs unchanged',array(lib.tabsof('p~b')),['chat','space','memory','routines']);
check('regular bot tabs unchanged',array(lib.tabsof('other')),['chat','mail','space','browser','tasks','memory','routines','hooks','settings']);
console.log(JSON.stringify({pass:true,checks:count,scope:'executed emitted shared selection, web render tree and phone JSON; no service/providers/live data'}));
