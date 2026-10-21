'use strict';
const assert=require('node:assert/strict'),{test}=require('node:test'),a=require('../compose-target-freeze.cjs');
test('freeze composition cannot receive relative or duplicate artifact paths',()=>{
  assert.throws(()=>a.options(['--policy','p','--components','c','--service','s','--out','o']),/Absolute/);
  assert.throws(()=>a.options([]),/Use/);
});
test('untrusted staging policy is rejected before artifact composition',()=>{
  assert.throws(()=>a.policyIdentity({}, {},'0'.repeat(64)),/Untrusted root/);
  assert.throws(()=>a.policyIdentity({kind:'wrong'}, {},'2376fa34e8ba5c786b23056392cd35730ce5a2c4c09982868cd7db89dcd510dd'));
});
