'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const p=require('../produce-release.cjs'),sample=JSON.parse(fs.readFileSync(path.join(__dirname,'fixtures/windows-native-mode-mismatch.json')));
const file=(mode=0o664)=>({type:'file',sha256:'a'.repeat(64),bytes:123,mode});
test('actual Windows shell and Electron mode-only failures compare without changing source receipts',()=>{
 for(const group of Object.values(sample.components)){
  assert(group.onlyMode);assert.equal(group.actualMembers,group.expectedMembers);
  const expected=Object.fromEntries(group.differences.map(d=>[d.name,d.expected])),actual=Object.fromEntries(group.differences.map(d=>[d.name,d.actual]));
  assert.notEqual(p.canonical(actual),p.canonical(expected));const before=JSON.stringify(expected);
  assert.equal(p.canonical(actual),p.canonical(p.membershipExpectation(expected,'windows-x64','win32')));assert.equal(JSON.stringify(expected),before);
 }
});
test('native Windows comparison models only the read-only attribute, including PE execute bits',()=>{
 for(const mode of [0o644,0o664,0o666,0o755,0o777])assert.equal(p.membershipExpectation({x:file(mode)},'windows-x64','win32').x.mode,0o666);
 for(const mode of [0o444,0o555])assert.equal(p.membershipExpectation({x:file(mode)},'windows-x64','win32').x.mode,0o444);
 assert.notEqual(p.canonical({x:file(0o777)}),p.canonical(p.membershipExpectation({x:file(0o777)},'windows-x64','win32')));
});
test('Unix targets and Windows artifacts inspected on Unix retain exact POSIX mode comparison',()=>{
 const members={x:file()};for(const [target,host]of [['linux-x64','linux'],['linux-arm64','linux'],['darwin-arm64','darwin'],['windows-x64','linux'],['linux-x64','win32']])assert.equal(p.membershipExpectation(members,target,host),members);
 assert.notEqual(p.canonical(members),p.canonical({x:file(0o666)}));
});
test('native Windows projection refuses declared privileged modes, invalid modes and link types',()=>{
 for(const mode of [0o4755,0o1000,-1,1.5,'644'])assert.throws(()=>p.membershipExpectation({x:file(mode)},'windows-x64','win32'),/mode/);
 for(const type of ['symlink','junction','directory'])assert.throws(()=>p.membershipExpectation({x:{...file(),type}},'windows-x64','win32'),/symlink/);
});
test('path sets, file types, sizes, digests and extra fields still compare exactly',()=>{
 const normalized=p.membershipExpectation({x:file()},'windows-x64','win32');for(const actual of [{y:file(0o666)},{x:{...file(0o666),bytes:124}},{x:{...file(0o666),sha256:'b'.repeat(64)}},{x:{...file(0o666),type:'symlink'}},{x:file(0o666),extra:file(0o666)},{x:{...file(0o666),extra:true}}])assert.notEqual(p.canonical(actual),p.canonical(normalized));
});

test('copied Electron runtime uses native-host membership projection with unchanged type/hash/size checks',()=>{
 const source=fs.readFileSync(path.join(__dirname,'../produce-release.cjs'),'utf8');
 assert(source.includes('for(const [n,expected]of Object.entries(membershipExpectation(electron.receipt.members,target)))'));
 assert(!source.includes('for(const [n,expected]of Object.entries(electron.receipt.members))'));
 assert(source.includes("st.isFile()&&digest(dest)===expected.sha256&&st.size===expected.bytes&&(st.mode&0o777)===expected.mode"));
 const expected={runtime:{type:'file',sha256:'c'.repeat(64),bytes:987,mode:0o777}},before=JSON.stringify(expected);
 const projected=p.membershipExpectation(expected,'windows-x64','win32');assert.deepEqual(projected.runtime,{...expected.runtime,mode:0o666});assert.equal(JSON.stringify(expected),before);
 assert.equal(p.membershipExpectation(expected,'linux-x64','linux'),expected);
});
