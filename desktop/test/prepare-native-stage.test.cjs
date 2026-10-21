'use strict';
const assert=require('node:assert/strict'),{test}=require('node:test'),path=require('node:path');
const a=require('../prepare-native-stage.cjs');
test('stage cannot receive relative or repeated artifact paths',()=>{
  assert.throws(()=>a.options(['--components','x','--service','y','--freeze','z','--out','q']),/Absolute/);
  assert.throws(()=>a.options(['--components',path.resolve('x'),'--components',path.resolve('y'),'--freeze',path.resolve('z'),'--out',path.resolve('q')]),/duplicate/);
});
test('all four required actual artifact paths survive native path parsing',()=>{
  const names=['--components','--service','--freeze','--out'],args=names.flatMap((n,i)=>[n,path.resolve('native fixture 日本語',String(i))]);
  const result=a.options(args);for(let i=0;i<names.length;i++)assert.equal(result[names[i]],args[i*2+1]);
  assert.throws(()=>a.options(args.slice(0,-2)),/Expected/);
});
