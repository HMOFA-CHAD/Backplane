'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const presentation=(tag,attrs)=>({session:{sel:'t',drafts:{},rid:1},cmds:[],view:{type:'element',tag,key:'t',attrs,kids:[{type:'text',text:'日本語 é'}]}});
test('normal Bend sidebar memo accepts its inert empty and selected on flags',async()=>{
 const {validatePresentation}=await import('../../src/web/startup.js');
 for(const value of ['', '1']) assert.doesNotThrow(()=>validatePresentation(presentation('bp-memo',[
  {name:'fn',value:'row'},{name:'ago',value:''},{name:'badge',value:''},{name:'dot',value:'idle'},
  {name:'on',value},{name:'mov',value:''},{name:'lang',value:'en'},
 ])));
});
test('memo selection exception cannot admit executable or unrelated on attributes',async()=>{
 const {validatePresentation}=await import('../../src/web/startup.js');
 for(const tag of ['div','svg','bp-memo']) for(const name of ['onclick','onload','onerror','ON'])
  assert.throws(()=>validatePresentation(presentation(tag,[{name,value:'1'}])),/Invalid presentation attribute/);
 for(const value of ['0','true','alert(1)','1;anything'])
  assert.throws(()=>validatePresentation(presentation('bp-memo',[{name:'on',value}])),/Invalid presentation attribute/);
 assert.throws(()=>validatePresentation(presentation('div',[{name:'on',value:'1'}])),/Invalid presentation attribute/);
});
test('ordinary Bend event descriptors retain their existing validation path',async()=>{
 const {validatePresentation}=await import('../../src/web/startup.js');
 assert.doesNotThrow(()=>validatePresentation(presentation('button',[{event:'click',action:'select'}])));
});
