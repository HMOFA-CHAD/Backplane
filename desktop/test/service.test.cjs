const { test } = require('node:test');
const assert = require('node:assert/strict');
const { hello, lockLine, Service, preferredPort, servicePort } = require('../service.cjs');
test('decodes the real hello wire shape and rejects alien greetings', () => {
  assert.deepEqual(hello(Buffer.from('a1696261636b706c616e6565312e322e33', 'hex')), { backplane: '1.2.3' });
  assert.throws(() => hello(Buffer.from('a0', 'hex')));
  assert.throws(() => hello(Buffer.from('ff', 'hex')));
});
test('owned-service port allocation preserves origin across sequential app restarts', async t => {
  const net=require('node:net'),crypto=require('node:crypto');const home='/tmp/bp-owned-origin-'+crypto.randomUUID();
  const candidate=preferredPort(home),probe=net.createServer();
  try { await new Promise((resolve,reject)=>{probe.once('error',reject);probe.listen(candidate,'127.0.0.1',resolve);}); }
  catch(error){if(error.code==='EADDRINUSE'){t.skip('Preferred synthetic port already occupied');return;}throw error;}
  await new Promise(resolve=>probe.close(resolve));
  const first=await servicePort(home),second=await servicePort(home+'/child/..');assert.equal(first,candidate);assert.equal(second,first);
});
test('an occupied preferred port falls back without attaching to or signalling its owner', async()=>{
  const net=require('node:net'),crypto=require('node:crypto');const home='/tmp/bp-owned-collision-'+crypto.randomUUID(),server=net.createServer();
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(preferredPort(home),'127.0.0.1',resolve);});
  try { const chosen=await servicePort(home);assert.notEqual(chosen,server.address().port);assert(server.listening); }
  finally { await new Promise(resolve=>server.close(resolve)); }
});
test('discovery accepts only the existing explicit flock contract', () => {
  assert.deepEqual(lockLine('123 3787 flock\n'), { posixPid: 123, port: 3787 });
  for (const line of ['0 3787 flock', '123 65536 flock', '123 3787', '123 3787 flock\nextra']) assert.throws(() => lockLine(line));
});
test('does not signal a service it merely discovered', () => {
  const manager = new Service({ home: '/tmp/test-backplane-electron' });
  manager.connection = { pid: process.pid }; manager.stop();
  assert.equal(manager.child, null);
});
test('authenticates the endpoint without treating POSIX lock IDs as native PIDs', async () => {
  const http = require('node:http');
  const fs = require('node:fs/promises');
  const path = require('node:path');
  const os = require('node:os');
  const home = await fs.mkdtemp(path.join(os.tmpdir(),'bp-lock-identity-'));
  const token = 'a'.repeat(32);
  const server = http.createServer((req,res) => {
    if(req.url === '/hello') { res.end(Buffer.from('a1696261636b706c616e6565312e322e33','hex')); return; }
    res.statusCode=req.headers.authorization === `Bearer ${token}` ? 200 : 401; res.end();
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const port=server.address().port;
  try {
    await fs.writeFile(path.join(home,'token'),token);
    await fs.writeFile(path.join(home,'hub.lock'),`2147483647 ${port} flock\n`);
    const service=new Service({home,expectedVersion:'1.2.3'});
    const connection=await service.discover();
    assert.deepEqual(connection.lockIdentity,{posixPid:2147483647});
    assert.equal(service.child,null);
    await fs.writeFile(path.join(home,'token'),'b'.repeat(32));
    await assert.rejects(()=>service.discover(),/does not authenticate/);
  } finally { await new Promise(resolve=>server.close(resolve)); await fs.rm(home,{recursive:true,force:true}); }
});
