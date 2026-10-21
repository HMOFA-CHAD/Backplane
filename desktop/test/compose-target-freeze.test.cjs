'use strict';
const assert=require('node:assert/strict'),{test}=require('node:test'),a=require('../compose-target-freeze.cjs');
test('freeze composition cannot receive relative or duplicate artifact paths',()=>{
  assert.throws(()=>a.options(['--policy','p','--components','c','--service','s','--out','o']),/Absolute/);
  assert.throws(()=>a.options([]),/Use/);
});
test('untrusted staging policy is rejected before artifact composition',()=>{
  assert.throws(()=>a.policyIdentity({}, {},'0'.repeat(64)),/Untrusted root/);
  assert.throws(()=>a.policyIdentity({kind:'wrong'}, {},'0146a1527cd121ed04c8f36052ba0f31232176e56910387cb84f0dc97d7c4ef2'));
});
