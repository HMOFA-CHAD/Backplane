'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
function fixture(){
 const source=fs.readFileSync(path.resolve(__dirname,'../../src/web/host.js'),'utf8'),a=source.indexOf('function earlierCheck('),b=source.indexOf('document.addEventListener("click",',a),sent=[];
 class Element{constructor(){this.id='timeline';this.scrollTop=0;this.clientHeight=800;this.scrollHeight=2000;}closest(){return this;}querySelector(){return{getAttribute:()=> 'own-thread'};}getBoundingClientRect(){return{right:390};}}
 const ctx={Element,viewMode:'view-v1',earlierAsked:false,performance:{now:()=>1},document:{addEventListener(){},body:{}},dispatch:(a,v)=>sent.push({a,v})};vm.createContext(ctx);vm.runInContext(source.slice(a,b),ctx);const tl=new Element();return{ctx,tl,sent,event:(type,extra)=>ctx.noteOlderGesture({type,target:tl,isTrusted:true,...extra})};
}
test('render/initial scroll alone cannot start automatic older paging',()=>{
 const f=fixture();f.ctx.earlierCheck(f.tl);assert.equal(f.sent.length,0);
});
test('one real upward wheel gesture permits at most one older page',()=>{
 const f=fixture();f.event('wheel',{deltaY:-40});f.ctx.earlierCheck(f.tl);f.ctx.earlierAsked=false;f.ctx.earlierCheck(f.tl);assert.equal(f.sent.length,1);
});
test('downward scrolling and ordinary text clicks do not trigger older download',()=>{
 const f=fixture();f.event('wheel',{deltaY:40});f.ctx.earlierCheck(f.tl);f.event('pointerdown',{button:0,clientX:50});f.ctx.earlierCheck(f.tl);assert.equal(f.sent.length,0);
});
test('a finger movement toward older messages qualifies; a downward-reading gesture does not',()=>{
 const f=fixture();f.event('touchstart',{touches:[{clientY:100}]});f.event('touchmove',{touches:[{clientY:80}]});f.ctx.earlierCheck(f.tl);assert.equal(f.sent.length,0);f.event('touchmove',{touches:[{clientY:120}]});f.ctx.earlierCheck(f.tl);assert.equal(f.sent.length,1);
});
