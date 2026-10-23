// Sole-integrator isolated finding: what a cold desktop window first shows when
// the chosen theme is light. Never connect to the live user home.
// BACKPLANE_LOCAL_STAGE=<stage> node desktop/test/theme-cold-window.cjs
// Launch 1 lets the product learn and keep the theme (hub ui.theme=light).
// Launch 2 is the cold start on the same isolated profile: the window's own
// background, its first captured picture and every document's first animation
// frames (startup page, then the hub's page) are recorded. Passive: nothing is
// clicked, set or cleared in launch 2.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const {_electron}=require('playwright-core'),{Service}=require('../service.cjs');
const stage=path.resolve(process.env.BACKPLANE_LOCAL_STAGE),info=JSON.parse(fs.readFileSync(stage+'/LOCAL.json'));
const out=process.env.THEME_COLD_OUT||path.join(stage,'theme-cold-'+Date.now());fs.mkdirSync(out,{recursive:true});
const home=fs.mkdtempSync(path.join(os.tmpdir(),'bp-theme-cold-')),agents=path.join(home,'agents'),root=path.join(home,'board');fs.mkdirSync(agents);fs.mkdirSync(root);
for(const name of ['claude','codex','grok','muse','agy','opencode'])fs.writeFileSync(path.join(agents,name),'#!/bin/sh\nexit 127\n',{mode:0o755});
const at=Math.floor(Date.now()/1000),events=[],ev=($,fields)=>events.push({$,...fields,at});
ev('ProjectCreated',{id:'board',title:'Board',root});ev('ThreadCreated',{id:'ta',title:'Thread ta',project:'board',env:'local',branch:'',worktree:root,provider:'codex',model:''});
for(const [key,value] of [['restart.continue','off'],['mail.on','off'],['telemetry.share','off'],['onboard.done','1'],['ui.theme','light']])ev('SettingSet',{key,value});
fs.writeFileSync(home+'/events.jsonl',events.map(JSON.stringify).join('\n')+'\n');
const env={...process.env,BACKPLANE_HOME:home,BACKPLANE_AGENTS:agents,BACKPLANE_COPY:'1',BACKPLANE_TELEMETRY:'off',BACKPLANE_NO_UPDATE:'1',BACKPLANE_PEERS:'',BACKPLANE_LOCK_DIR:home+'/locks',SHELL:'/bin/sh'};Object.assign(process.env,env);
const binary=stage+'/payload/backplane-serve',web=stage+'/payload/web',service=new Service({home,binary,web,expectedVersion:info.version});
const LIGHT=[250,250,248];
const recorder=`(()=>{let n=0;const f=()=>{if(n++>=12)return;const s=getComputedStyle(document.documentElement);
 console.log('THEMEFRAME '+JSON.stringify({n,url:location.protocol+'//'+location.host+location.pathname,bg:s.backgroundColor,body:document.body?getComputedStyle(document.body).backgroundColor:'',htmlLight:document.documentElement.classList.contains('light'),app:document.querySelector('.app')?.className||''}));requestAnimationFrame(f);};requestAnimationFrame(f);})();`;
const launch=()=>_electron.launch({executablePath:stage+'/desktop/runtime/backplane-desktop',env:{...env,BACKPLANE_SERVICE:binary,BACKPLANE_WEB:web,BACKPLANE_SERVICE_VERSION:info.version}});
const near=(rgb,want)=>rgb.every((v,i)=>Math.abs(v-want[i])<=6);
(async()=>{let app,step='launch-1';const r={source:info.commit,stage,home,liveProfileTouched:false};try{
 await service.start();
 app=await launch();let page=await app.firstWindow();page.setDefaultTimeout(20000);
 await page.waitForFunction(()=>document.documentElement.dataset.backplaneRemoteReady==='true'&&document.querySelector('.app.light'));
 await page.evaluate(()=>new Promise(r=>setTimeout(r,300)));
 r.kept=await page.evaluate(()=>({localStorage:localStorage.getItem('backplane-theme')}));await app.close();app=null;
 step='launch-2-cold';const frames=[];
 app=await launch();await app.context().addInitScript(recorder).catch(()=>{});
 app.context().on('console',m=>{const t=m.text();if(t.startsWith('THEMEFRAME '))frames.push(JSON.parse(t.slice(11)));});
 const first=await app.evaluate(async({BrowserWindow})=>{const w=BrowserWindow.getAllWindows()[0];
  const shot=await w.webContents.capturePage();const {width,height}=shot.getSize(),bmp=shot.toBitmap();
  const px=(x,y)=>{const i=(y*width+x)*4;return [bmp[i+2],bmp[i+1],bmp[i]];};
  return{visible:w.isVisible(),windowBackground:w.getBackgroundColor(),url:w.webContents.getURL(),size:[width,height],corner:width?px(4,4):null,centre:width?px(width>>1,height>>1):null,png:shot.toPNG().toString('base64')};});
 fs.writeFileSync(out+'/cold-first.png',Buffer.from(first.png,'base64'));delete first.png;r.first=first;
 page=await app.firstWindow();await page.evaluate(()=>{}).catch(()=>{});
 // the startup page was loaded before the init script could be added: read it directly too
 r.startupNow=await page.evaluate(()=>({url:location.protocol+'//'+location.pathname.split('/').pop(),bg:getComputedStyle(document.documentElement).backgroundColor,htmlLight:document.documentElement.classList.contains('light')})).catch(e=>({error:String(e)}));
 await page.waitForFunction(()=>document.documentElement.dataset.backplaneRemoteReady==='true',null,{timeout:20000}).catch(()=>{});
 await page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)))).catch(()=>{});
 r.frames=frames;
 const dark=[...(first.corner&&!near(first.corner,LIGHT)?[{where:'first captured window picture',rgb:first.corner,url:first.url}]:[]),
  ...(first.windowBackground&&!/^#?fafaf8/i.test(first.windowBackground)?[{where:'BrowserWindow backgroundColor',value:first.windowBackground}]:[]),
  ...(r.startupNow?.bg&&r.startupNow.bg!=='rgb(250, 250, 248)'?[{where:'startup page',bg:r.startupNow.bg}]:[]),
  ...frames.filter(f=>f.bg!=='rgb(250, 250, 248)').map(f=>({where:'document frame',...f}))];
 r.state=dark.length?'finding':'light-throughout';r.notLight=dark;
 fs.writeFileSync(out+'/RESULT.json',JSON.stringify(r,null,2)+'\n');console.log(JSON.stringify({state:r.state,kept:r.kept,first:r.first,notLight:dark.slice(0,6)}));
}catch(e){fs.writeFileSync(out+'/FAIL.json',JSON.stringify({...r,state:'failed',step,error:e.stack},null,2)+'\n');console.error(e.stack);process.exitCode=1;}
finally{if(app)await app.close().catch(()=>{});await service.stop();}})();
