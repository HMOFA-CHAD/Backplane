'use strict';
const assert=require('node:assert/strict'),{test}=require('node:test'),a=require('../compose-target-freeze.cjs');
test('freeze composition cannot receive relative or duplicate artifact paths',()=>{
  assert.throws(()=>a.options(['--policy','p','--components','c','--service','s','--out','o']),/Absolute/);
  assert.throws(()=>a.options([]),/Use/);
});
test('untrusted staging policy is rejected before artifact composition',()=>{
  assert.throws(()=>a.policyIdentity({}, {},'0'.repeat(64)),/Untrusted root/);
  assert.throws(()=>a.policyIdentity({kind:'wrong'}, {},'6f7a2a7e509e94fc67e1b670d4523a7ab3872a5fbc211661a5a956c71c7174bb'));
});
