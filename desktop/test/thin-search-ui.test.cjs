'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=fs.readFileSync(path.resolve(__dirname,'../../src/web/host.js'),'utf8');
function trigger(mode,ready){
 const a=source.indexOf('function dispatch('),b=source.indexOf('  if (viewMode !== "compatibility")',a),panels=[],status=[];
 const ctx={viewMode:mode,thin:{ready},showThinSearch:x=>panels.push(x),showViewStatus:x=>status.push(x)};vm.createContext(ctx);vm.runInContext(source.slice(a,b)+'return false;}',ctx);
 return{ctx,panels,status};
}
test('human search entry opens an empty dialog only on a current thin connection, without any query',()=>{
 const f=trigger('view-v1',true);assert.equal(f.ctx.dispatch('thin-search-open',''),true);assert.equal(f.panels.length,1);assert.equal(f.panels[0].query,'');assert.equal(f.panels[0].rows.length,0);
});
test('cached, unready and compatibility search entry cannot query or acquire authority',()=>{
 for(const [mode,ready]of [['read-only',false],['view-v1',false],['compatibility',true]]){const f=trigger(mode,ready);f.ctx.dispatch('thin-search-open','');assert.equal(f.panels.length,0);assert.equal(f.status.length,1);}
});
function panelFixture(){
 class Element{constructor(tag){this.tag=tag;this.children=[];this.handlers={};this.style={};}append(...e){this.children.push(...e);}setAttribute(k,v){this[k]=v;}addEventListener(k,fn){this.handlers[k]=fn;}focus(){}}
 const panel=new Element('section'),calls=[],select=[];let closes=0;
 const ctx={resultPanel:()=>({panel,close:()=>closes++}),document:{createElement:tag=>new Element(tag)},thin:{search:(...args)=>calls.push(args)},dispatch:(...args)=>select.push(args)};
 const a=source.indexOf('function showThinSearch('),b=source.indexOf('function showThinMessage(',a);vm.createContext(ctx);vm.runInContext(source.slice(a,b),ctx);
 return{ctx,panel,calls,select,closes:()=>closes};
}
test('actual query field submits exact Unicode on Enter only after composition commit',()=>{
 const f=panelFixture();f.ctx.showThinSearch({query:'',rows:[],hasMore:false});const query=f.panel.children[0];query.value='日本語 é';query.handlers.keydown({key:'Enter',isComposing:true});assert.equal(f.calls.length,0);
 query.handlers.keydown({key:'Enter',isComposing:false,preventDefault(){}});assert.deepEqual(f.calls,[['日本語 é']]);
});
test('actual search rows select their original thread and More sends only explicit opaque cursor',()=>{
 const f=panelFixture();f.ctx.showThinSearch({query:'Japanese',rows:[{thread:'owner-B',text:'real match',partial:false}],hasMore:true,cursor:'exact-next'});
 assert.equal(f.calls.length,0);f.panel.children[2].handlers.click();assert.deepEqual(f.calls,[['Japanese','exact-next']]);f.panel.children[1].children[0].handlers.click();assert.deepEqual(f.select,[['select','owner-B']]);assert.equal(f.closes(),1);
});
test('owned Bend sidebar source exposes the named accessible human search control',()=>{
 const view=fs.readFileSync(path.resolve(__dirname,'../../src/web/view.bend'),'utf8');assert(view.includes('WI.WIcon.button("icon", "thin-search-open", "", "Search conversations", "search", 16, "")'));
});
