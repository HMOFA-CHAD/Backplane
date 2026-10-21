'use strict';
const assert=require('node:assert/strict'),{test}=require('node:test'),a=require('../compose-target-freeze.cjs');
test('freeze composition cannot receive relative or duplicate artifact paths',()=>{
  assert.throws(()=>a.options(['--policy','p','--components','c','--service','s','--out','o']),/Absolute/);
  assert.throws(()=>a.options([]),/Use/);
});
test('untrusted staging policy is rejected before artifact composition',()=>{
  assert.throws(()=>a.policyIdentity({}, {},'0'.repeat(64)),/Untrusted root/);
  assert.throws(()=>a.policyIdentity({kind:'wrong'}, {},'c1b1f1be2e6baf3a4fe719e05eb4dd01aaa160ed67dacaf3c85e6e60779221d9'));
});
