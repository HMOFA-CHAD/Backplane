'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=fs.readFileSync(process.env.HOST_SOURCE||path.resolve(__dirname,'../../src/web/host.js'),'utf8');
function fixture(){
 const a=source.indexOf('function setAttrs('),b=source.indexOf('// A piece of the page',a);assert(a>0&&b>a);
 const attrs=new Map(),fields=new Map([['mrreply','new 日本語 👩‍💻 é\n']]);let writes=0,value='new 日本語 👩‍💻 é\n';
 const el={get value(){return value;},set value(v){writes++;value=v;},getAttribute:k=>attrs.get(k)??null,setAttribute:(k,v)=>attrs.set(k,v),removeAttribute:k=>attrs.delete(k)};
 const ctx={Set,is:(v,t)=>v?.$===t,each:function*(xs){for(let x=xs;x?.$==='Con';x=x.tail)yield x.head;},viewMode:'view-v1',frontendNode:{},thinMailDraft:{fieldValue:(_name,fallback)=>fallback},thin:{fieldValue:(name,fallback)=>fields.get(name)??fallback}};
 vm.createContext(ctx);vm.runInContext(source.slice(a,b),ctx);
 const list=items=>items.reduceRight((tail,head)=>({$:'Con',head,tail}),{$:'Nil'}),at=(name,value)=>({$:'At',name,value});
 return {ctx,el,fields,attrs,getWrites:()=>writes,patch:items=>ctx.setAttrs(el,list([]),list(items.map(([k,v])=>at(k,v))))};
}
test('real host attribute adapter preserves newer Unicode and native selection by avoiding a value write',()=>{
 const f=fixture();f.patch([['value','old captured body'],['data-bfield','mrreply']]);assert.equal(f.el.value,'new 日本語 👩‍💻 é\n');assert.equal(f.getWrites(),0);
});
test('real host attribute adapter uses the new field identity rather than recycled DOM attributes',()=>{
 const f=fixture();f.attrs.set('data-bfield','mrreply');f.patch([['value','different owner'],['data-bfield','other']]);assert.equal(f.el.value,'different owner');
});
test('real host attribute adapter preserves an intentionally emptied local field',()=>{
 const f=fixture();f.fields.set('mrreply','');f.patch([['data-bfield','mrreply'],['value','old']]);assert.equal(f.el.value,'');
});
test('real host attribute adapter never injects local field values into a cached or compatibility view',()=>{
 for(const mode of ['read-only','compatibility']){const f=fixture();f.ctx.viewMode=mode;f.patch([['data-bfield','mrreply'],['value','server']]);assert.equal(f.el.value,'server');}
 const f=fixture();f.ctx.frontendNode=null;f.patch([['data-bfield','mrreply'],['value','picture']]);assert.equal(f.el.value,'picture');
});
test('real host attribute adapter returns to the authoritative value when acknowledged overlay retires',()=>{
 const f=fixture();f.fields.delete('mrreply');f.patch([['data-bfield','mrreply'],['value','']]);assert.equal(f.el.value,'');assert.equal(f.getWrites(),1);
});
