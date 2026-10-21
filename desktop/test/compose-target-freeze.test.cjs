'use strict';
const assert=require('node:assert/strict'),{test}=require('node:test'),a=require('../compose-target-freeze.cjs');
test('freeze composition cannot receive relative or duplicate artifact paths',()=>{
  assert.throws(()=>a.options(['--policy','p','--components','c','--service','s','--out','o']),/Absolute/);
  assert.throws(()=>a.options([]),/Use/);
});
test('untrusted staging policy is rejected before artifact composition',()=>{
  assert.throws(()=>a.policyIdentity({}, {},'0'.repeat(64)),/Untrusted root/);
  assert.throws(()=>a.policyIdentity({kind:'wrong'}, {},'fc3aba8aa6e58fabf0f91cd995bd6485f8e35215bb2f1dfa7dc642e4e4c8a335'));
});
