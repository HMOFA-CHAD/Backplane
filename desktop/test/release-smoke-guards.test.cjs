'use strict';
const assert=require('node:assert/strict'),{test}=require('node:test');
const {argumentsFor,journalCheck,hostTarget}=require('./release-smoke.cjs');
test('help and native host identity do not launch a payload',()=>{
  assert.equal(argumentsFor(['--help']),null);
  assert.equal(hostTarget(),`${process.platform==='win32'?'windows':process.platform}-${process.arch}`);
});
test('relative paths and duplicate options cannot select a stage/home',()=>{
  assert.throws(()=>argumentsFor(['--stage','relative','--out','relative']),/Absolute/);
  assert.throws(()=>argumentsFor(['--stage','/x','--stage','/y']),/duplicate/);
});
test('the smoke journal guard rejects every send/wake path and enabling automation',()=>{
  const before=Buffer.from(JSON.stringify({$:'SettingSet',key:'mail.on',value:'off'})+'\n');
  const after=event=>Buffer.concat([before,Buffer.from(JSON.stringify(event)+'\n')]);
  assert.equal(journalCheck(before,before).noSendOrAgentTurn,true);
  for(const kind of ['MailPosted','RoomPosted','MessagePosted','RunSet','BotWoke','TurnQueued'])assert.throws(()=>journalCheck(before,after({$:kind})),/send or wake/);
  for(const key of ['mail.on','telemetry.share'])assert.throws(()=>journalCheck(before,after({$:'SettingSet',key,value:'on'})),/enabled/);
  assert.throws(()=>journalCheck(before,Buffer.from('bad')),/prefix/);
});
