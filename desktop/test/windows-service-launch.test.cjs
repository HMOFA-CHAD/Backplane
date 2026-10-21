'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),path=require('node:path'),fs=require('node:fs'),vm=require('node:vm'),{EventEmitter}=require('node:events'),{promisify}=require('node:util');
const {launchPaths}=require('../service.cjs');
const binary='C:\\Backplane Release 日本\\resources\\backplane-service\\backplane-serve.exe';
const home='C:\\Users\\Person\\Private home 日本',web=path.win32.join(path.win32.dirname(binary),'web');
const mapped=n=>'/proc/cygdrive/'+n[0].toLowerCase()+n.slice(2).replaceAll('\\','/');
function mapper(calls){return async(file,args,options)=>{calls.push({file,args,options});return {stdout:mapped(args.at(-1))+'\r\n',stderr:''};};}
test('private DLL path excludes ambient PATH and absolute shipped cygpath maps only child paths',async()=>{
 const env={SystemRoot:'C:\\Windows',Path:'C:\\Windows\\System32;C:\\Foreign Cygwin',BACKPLANE_HOME:home,BACKPLANE_AGENTS:home+'\\agents',BACKPLANE_LOCK_DIR:home+'\\locks',KEEP:'unchanged',LC_ALL:'C'},before=JSON.stringify(env),calls=[];
 const r=await launchPaths({binary,home,web,env,platform:'win32',run:mapper(calls)});
 const bin=path.win32.join(path.win32.dirname(binary),'runtime','bin');
 assert.equal(r.home,mapped(home));assert.equal(r.web,mapped(web));assert.equal(r.env.PATH,bin+';C:\\Windows\\System32;C:\\Windows');assert(!r.env.PATH.includes('Foreign'));assert.equal(r.cwd,bin);assert(!('Path'in r.env));
 assert.equal(r.env.BACKPLANE_HOME,mapped(home));assert.equal(r.env.BACKPLANE_AGENTS,mapped(env.BACKPLANE_AGENTS));assert.equal(r.env.BACKPLANE_LOCK_DIR,mapped(env.BACKPLANE_LOCK_DIR));assert.equal(r.env.KEEP,'unchanged');assert.equal(r.env.LC_ALL,'C.UTF-8');assert.equal(JSON.stringify(env),before);
 assert.equal(calls.length,4);for(const c of calls){assert.equal(c.file,path.win32.join(bin,'cygpath.exe'));assert.deepEqual(c.args.slice(0,4),['-a','-u','--',c.args[3]]);assert.equal(c.options.shell,false);assert.equal(c.options.windowsHide,true);assert.equal(c.options.timeout,5000);assert.equal(c.options.encoding,'utf8');assert.equal(c.options.env.LC_ALL,'C.UTF-8');assert.equal(c.options.cwd,bin);assert(c.options.env.PATH.startsWith(bin+';'));}
});
test('Unix launch preserves exact native argv and environment without running helper',async()=>{
 const env={PATH:'/unchanged',BACKPLANE_HOME:'/tmp/home'};
 for(const platform of ['linux','darwin']){const r=await launchPaths({binary:'/opt/backplane',home:'/tmp/home',web:'/opt/web',env,platform,run:()=>{throw Error('must not run');}});assert.equal(r.env,env);assert.deepEqual(r,{home:'/tmp/home',web:'/opt/web',env});}
});
test('path conversion refuses relative/drive-relative/control input and malformed or failed helper output',async()=>{
 for(const bad of ['relative','C:relative','\\root-relative','C:\\bad\npath'])await assert.rejects(()=>launchPaths({binary,home:bad,web,env:{SystemRoot:'C:\\Windows'},platform:'win32',run:mapper([])}),/fully qualified/);
 await assert.rejects(()=>launchPaths({binary,home,web,env:{SystemRoot:'relative'},platform:'win32',run:mapper([])}),/SystemRoot/);
 await assert.rejects(()=>launchPaths({binary:binary.replace('Backplane Release','Backplane;Foreign'),home,web,env:{SystemRoot:'C:\\Windows'},platform:'win32',run:mapper([])}),/PATH separator/);
 for(const stdout of ['C:\\still-native','/ok\n/injected','/bad\0tail',''])await assert.rejects(()=>launchPaths({binary,home,web,env:{SystemRoot:'C:\\Windows'},platform:'win32',run:async()=>({stdout})}),/conversion/);
 await assert.rejects(()=>launchPaths({binary,home,web,env:{SystemRoot:'C:\\Windows'},platform:'win32',run:async()=>{throw Error('secret stderr must not leak');}}),e=>e.message==='Cannot map paths with the packaged Windows runtime');
});
test('actual Service.start wires mapped argv/env into captured native child, while discovery reads native home',async()=>{
 const calls=[],reads=[],spawnCalls=[];let spawned=false;
 const child=new EventEmitter();Object.assign(child,{pid:10076,exitCode:null,signalCode:null,unref(){}});
 function execFile(){}execFile[promisify.custom]=mapper(calls);
 const fakeFs={mkdir:async()=>{},readFile:async(p)=>{reads.push(p);if(p===path.win32.join(home,'token'))return 'a'.repeat(32);if(!spawned)throw Object.assign(Error('missing'),{code:'ENOENT'});return '777777 45678 flock\n';}};
 const net={createServer:()=>({once(){},listen(port,host,cb){this.port=port;queueMicrotask(cb);},address(){return {port:this.port};},close(cb){cb();}})};
 const fakeProcess={platform:'win32',env:{SystemRoot:'C:\\Windows',Path:'C:\\Foreign Cygwin',BACKPLANE_AGENTS:home+'\\agents',BACKPLANE_LOCK_DIR:home+'\\locks'}};
 const context={require:n=>n==='node:fs/promises'?fakeFs:n==='node:path'?path.win32:n==='node:net'?net:n==='node:child_process'?{execFile,spawn:(file,args,options)=>{spawnCalls.push({file,args,options});spawned=true;return child;}}:require(n),module:{exports:{}},process:fakeProcess,Buffer,URL,AbortSignal,setTimeout,clearTimeout,fetch:async(url,options)=>url.endsWith('/hello')?{ok:true,arrayBuffer:async()=>Buffer.from('a1696261636b706c616e6566302e31322e30','hex')}:{ok:options.headers.Authorization==='Bearer '+'a'.repeat(32)}};
 vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../service.cjs'),'utf8'),context);
 const service=new context.module.exports.Service({binary,home,web,expectedVersion:'0.12.0',residentService:true});await service.start();
 assert.equal(spawnCalls.length,1);const launch=spawnCalls[0];assert.equal(launch.file,binary);assert.equal(launch.args[1],mapped(home));assert.equal(launch.args[7],mapped(web));assert.equal(launch.options.env.BACKPLANE_HOME,mapped(home));assert.equal(launch.options.env.BACKPLANE_NO_UPDATE,'1');assert.equal(launch.options.env.LC_ALL,'C.UTF-8');assert.equal(launch.options.cwd,path.win32.join(path.win32.dirname(binary),'runtime','bin'));assert(!launch.options.env.PATH.includes('Foreign'));assert.equal(launch.options.detached,true);assert.equal(launch.options.windowsHide,true);
 assert.equal(service.home,home);assert(reads.every(p=>p.startsWith(home+'\\')));assert.equal(service.child,child);assert.equal(service.connection.lockIdentity.posixPid,777777);assert.notEqual(service.child.pid,777777);
});
