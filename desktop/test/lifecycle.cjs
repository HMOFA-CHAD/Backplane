// Deliberately slow HTTP service fixture: measures first visible window only.
// It is not a replacement for the real Bend integration suite.
const { _electron }=require('playwright-core');
const fs=require('node:fs');const os=require('node:os');const path=require('node:path');const http=require('node:http');const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..'), home=fs.mkdtempSync(path.join(os.tmpdir(),'bp-electron-slow-'));
const token='a'.repeat(32), version='slow-fixture';
const hello=Buffer.concat([Buffer.from('a1696261636b706c616e65','hex'),Buffer.from([0x60+version.length]),Buffer.from(version)]);
fs.writeFileSync(path.join(home,'token'),token);
let app,firstHelloAt,helloReturnedAt;
const readyAfter=Date.now()+3000;
const server=http.createServer((req,res)=>{
  if(req.url==='/hello'){firstHelloAt??=Date.now();if(Date.now()<readyAfter){res.statusCode=503;res.end();return;}helloReturnedAt=Date.now();res.end(hello);return;}
  if(req.url==='/auth/pair'){res.statusCode=req.headers.authorization===`Bearer ${token}`?200:401;res.setHeader('Set-Cookie',`bp_token=${token}; Path=/; HttpOnly; SameSite=Strict`);res.end();return;}
  res.setHeader('Content-Type','text/html');res.end('<!doctype html><h1>Connected lifecycle fixture</h1>');
});
(async()=>{
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  fs.writeFileSync(path.join(home,'hub.lock'),`${process.pid} ${server.address().port} flock\n`);
  const started=Date.now(),out=path.join(root,'build/electron-evidence');fs.mkdirSync(out,{recursive:true});
  try{
    app=await _electron.launch({executablePath:require('electron'),args:[path.join(root,'desktop')],env:{...process.env,BACKPLANE_HOME:home,BACKPLANE_SERVICE_VERSION:version,DISPLAY:process.env.DISPLAY||':0'}});
    const page=await app.firstWindow();
    const visibleAt=await app.evaluate(({BrowserWindow})=>new Promise(resolve=>{const win=BrowserWindow.getAllWindows()[0];if(win.isVisible())resolve(Date.now());else win.once('show',()=>resolve(Date.now()));}));
    assert(!helloReturnedAt,'window is visible before deliberately slow readiness');
    await page.locator('#status').waitFor();
    await page.screenshot({path:path.join(out,'startup.png')});
    const denied=await page.evaluate(()=>window.backplaneDesktop.chooseFolder().then(()=>false,()=>true));assert(denied,'startup page has no folder privilege');
    await page.getByText('Connected lifecycle fixture',{exact:true}).waitFor({timeout:15000});
    const receipt={status:'passed',fixture:'delayed HTTP greeting; no Bend workload claim',firstVisibleElapsedMs:visibleAt-started,delayMs:3000,firstHelloAt,helloReturnedAt,startupPrivilegedIPCRejected:denied};
    fs.writeFileSync(path.join(out,'lifecycle.json'),JSON.stringify(receipt,null,2));console.log(JSON.stringify(receipt));
  }finally{if(app)await app.close();await new Promise(resolve=>server.close(resolve));}
})().catch(error=>{console.error(error);process.exitCode=1;});
