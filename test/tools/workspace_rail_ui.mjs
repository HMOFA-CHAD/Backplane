// Paired production Bend DOM + production keyed patcher in an isolated browser.
// No production hub, provider, Browser helper, PTY or user profile is touched.
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from '/home/h/.bun/install/cache/playwright-core@1.64.1@@@1/index.mjs';
const root=process.cwd(), out=process.env.WORKSPACE_UI_OUT||'/home/h/Documents/i2cjak/bp-coord/workspace-rail/evidence';
fs.mkdirSync(out,{recursive:true});
const F=(await import(process.env.WORKSPACE_FIXTURE||'file:///home/h/Documents/i2cjak/bp-coord/workspace-rail/fixture.mjs')).default;
const host=fs.readFileSync('src/web/host.js','utf8');
const patcher=host.slice(host.indexOf('const SVG_NS ='),host.indexOf('// Timing, for a bench only:'));
const menu=fs.readFileSync('src/web/workspace-menus.js','utf8');
const browserCode=`const T={El:'El',Txt:'Txt',At:'At',On:'On'},is=(v,n)=>v?.$===n;
function* each(list){for(let xs=list;xs&&is(xs,'Con');xs=xs.tail)yield xs.head;}
let viewMode='compatibility',frontendNode=null;const App={cat:n=>window.cats[n],make:k=>k};
${patcher}
const list=xs=>xs.reduceRight((tail,head)=>({$:'Con',head,tail}),{$:'Nil'});
function vnode(n){return n.type==='text'?{$:'Txt',text:n.text}:{$:'El',tag:n.tag,key:n.key,attrs:list(n.attrs.map(a=>a.event?{$:'On',event:a.event,action:a.action}:{$:'At',name:a.name,value:a.value})),kids:list(n.kids.map(vnode))}}
const root=document.getElementById('root');root.__v={$:'El',tag:'div',key:'',attrs:{$:'Nil'},kids:{$:'Nil'}};root.__kids=[];
window.ready=async(action,value)=>{const d=await fetch('/data'+location.search,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action,value})}).then(r=>r.json());window.cats=d.cats;window.last=d.state;patch(root,{$:'El',tag:'div',key:'',attrs:{$:'Nil'},kids:list([vnode(d.node)])});document.querySelector('.app')?.classList.toggle('light',new URLSearchParams(location.search).get('theme')==='light');window.uiReady=true;};
${menu.replace('export function','function')}
installWorkspaceMenus();
document.addEventListener('click',e=>{const b=e.target.closest('[data-on-click]');if(b){e.preventDefault();window.lastAction=[b.dataset.onClick,b.dataset.value||''];window.pending=window.ready(...window.lastAction)}});
document.addEventListener('input',e=>{if(e.target.id==='composer')window.pending=window.ready('draft',e.target.value)});
window.ready();`;
const sessions=new Map();
function cats(n,c={}){if(n.type==='element'){for(const a of n.attrs)if(a.name==='data-cat')c[a.value]=F.cat(a.value);n.kids.forEach(k=>cats(k,c))}return c}
const server=Bun.serve({hostname:'127.0.0.1',port:0,async fetch(req){const url=new URL(req.url),q=url.searchParams,key=q.toString();
 if(url.pathname==='/'){return new Response(`<!doctype html><html><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><link rel="stylesheet" href="/style?before=${q.get('before')||'0'}"><body><div id="root"></div><script type="module" src="/fixture.js"></script></body></html>`,{headers:{'Content-Type':'text/html'}})}
 if(url.pathname==='/style')return new Response(fs.readFileSync(q.get('before')==='1'?out+'/before/style.css':'src/web/style.css'),{headers:{'Content-Type':'text/css'}});
 if(url.pathname==='/fixture.js')return new Response(browserCode,{headers:{'Content-Type':'text/javascript'}});
 if(url.pathname==='/data'){let u=sessions.get(key)||F.scenario(F.start(q.get('bot')==='1',q.get('view')||''),q.get('scenario')||'');const p=await req.json();if(p.action==='fixture-stream')u=F.stream(u,p.value);else if(p.action)u=F.step(u,p.action,p.value);sessions.set(key,u);const node=JSON.parse(F.frame(q.get('before')==='1',q.get('bot')==='1',u));return Response.json({node,cats:cats(node),state:JSON.parse(F.state(u))})}
 if(url.pathname==='/identity')return Response.json(JSON.parse(F.board_identity()));
 if(url.pathname==='/boards')return Response.json(JSON.parse(F.board_case(BigInt(q.get('n')||'0'))));
 return new Response('',{status:404});}});
const browser=await chromium.launch({headless:true,executablePath:'/home/h/.cache/ms-playwright/chromium-1234/chrome-linux64/chrome',args:['--no-sandbox','--disable-dev-shm-usage']});
const checks=[],errors=[];const check=(name,ok,detail)=>{checks.push({name,ok,detail});console.log((ok?'ok ':'FAIL ')+name+(ok?'':' '+JSON.stringify(detail)))};
const page=await browser.newPage({viewport:{width:1440,height:1000}});page.setDefaultTimeout(8000);page.on('pageerror',e=>errors.push(String(e)));
async function load(q){await page.goto(`http://127.0.0.1:${server.port}/?${q}`);await page.waitForFunction(()=>window.uiReady);}
async function act(selector){await page.locator(selector).click();await page.evaluate(()=>window.pending);}
try{
 for(const before of [true,false])for(const width of [320,360,390,1024,1440])for(const bot of [false,true]){
  if(before&&bot)continue;
  await page.setViewportSize({width,height:900});await load(`before=${before?1:0}&bot=${bot?1:0}&width=${width}`);
  const dimensions=await page.evaluate(()=>({width:innerWidth,scroll:document.documentElement.scrollWidth,header:document.querySelector('.thread-head').getBoundingClientRect().height,composer:document.querySelector('.composer').getBoundingClientRect().bottom}));
  if(!before){check(`${width}/${bot?'bot':'thread'}: no page horizontal overflow`,dimensions.scroll<=width,dimensions);check(`${width}/${bot?'bot':'thread'}: composer within viewport`,dimensions.composer<=902,dimensions);check(`${width}/${bot?'bot':'thread'}: no duplicate live status`,await page.locator('#timeline > .phase').count()===0);}
  if(!before&&bot&&width<761){check(`${width}: bot pages share header`,await page.locator('.bot-head .bot-mobile-menu').isVisible());await page.locator('.bot-head .bot-mobile-menu summary').click();check(`${width}: bot page actions reachable`,await page.locator('.bot-mobile-menu [data-on-click=bot-tab]').first().isVisible());await page.keyboard.press('Escape');}
  if([360,1440].includes(width))await page.screenshot({path:`${out}/${before?'before':'after'}-${bot?'bot':'thread'}-${width}.png`});
 }
 await page.setViewportSize({width:1440,height:1000});await load('flow=1');
 check('draft present initially',await page.locator('#composer').inputValue()==='Unsent fixture draft');
 const picks=[['view-kind','board','board'],['view-kind','schematic','schematic'],['view-kind','3d','3d'],['mech','','3d'],['fm','','files'],['diff','','diff'],['rv-page','bom','review'],['view-kind','browser','browser']];
 for(const [action,value,kind] of picks){await act(`.workspace-rail [data-on-click="${action}"][data-value="${value}"]`);const state=await page.evaluate(()=>window.last);check(`destination ${action}/${value} preserves draft`,state.draft==='Unsent fixture draft',state);check(`destination ${action}/${value} invokes existing action`,(await page.evaluate(()=>window.lastAction))[0]===action);}
 await act('.workspace-rail [data-on-click="term-toggle"]');check('Terminal toggles with retained owner',await page.evaluate(()=>window.last.terminalOwner)==='t');await act('[data-on-click="ws-term-hide"]');check('hiding keeps owner identity',await page.evaluate(()=>window.last.terminalOwner)==='t');
 await act('.workspace-rail [data-on-click="ws-palette-open"]');check('Commands opens actual palette',await page.locator('.workspace-palette').count()===1);await act('[data-on-click="ws-palette-close"]');
 await page.locator('.thread-actions summary').click();check('thread management disclosed',await page.locator('.thread-actions [data-on-click="pin"]').isVisible());await act('.thread-actions [data-on-click="delete"]');check('Delete retains confirmation menu',await page.locator('.thread-actions[open] [data-on-click="delete-no"]').isVisible());await act('.thread-actions [data-on-click="delete-no"]');await page.keyboard.press('Escape');
 await page.locator('#composer').fill('Draft retained across menus and streaming');await page.evaluate(()=>window.pending);const field=await page.locator('#composer').elementHandle();await page.evaluate(()=>window.ready('fixture-stream','Streaming fixture text'));check('streaming preserves same composer node',await field.evaluate(el=>el===document.getElementById('composer')));check('streaming retains typed draft',await page.locator('#composer').inputValue()==='Draft retained across menus and streaming');check('real approval remains reachable',await page.locator('.asks').innerText().then(x=>x.includes('Approve')));check('real question remains reachable',await page.locator('.asks').innerText().then(x=>x.includes('Choose a board')));check('subagent dock remains discoverable',await page.locator('.subs-head').isVisible());check('failed sidebar thread remains reachable',await page.getByText('Failed thread remains reachable',{exact:true}).count()>0);
 await load('view=board&boards=1');await page.locator('.board-selector summary').click();check('exact duplicate path collapsed',await page.locator('[data-board-path]').count()===4);check('one current board by identity',await page.locator('.board-option.on').count()===1);await page.locator('[data-board-filter]').fill('sol-placement');check('distinct identical basenames retained',await page.locator('[data-board-path]:visible').count()===2);check('selector shows actual root',await page.locator('.board-origin').innerText().then(x=>x.includes('/tmp/navigation-fixture')));await page.keyboard.press('Escape');check('Escape returns selector focus',await page.locator('.board-selector summary').evaluate(x=>x===document.activeElement));await page.screenshot({path:`${out}/after-viewer-1440.png`});
 for(const width of [320,360,390]){await page.setViewportSize({width,height:844});await load(`phone=${width}`);await page.locator('.workspace-menu summary').click();check(`${width}: sheet fits`,await page.locator('.workspace-menu .local-menu-body').evaluate(x=>{const b=x.getBoundingClientRect();return b.left>=0&&b.right<=innerWidth}));check(`${width}: all ten destinations in sheet`,await page.locator('.workspace-menu button').count()===10);await page.keyboard.press('Escape');check(`${width}: menu focus restored`,await page.locator('.workspace-menu summary').evaluate(x=>x===document.activeElement));await page.locator('.workspace-menu summary').click();await act('.workspace-menu [data-on-click="view-kind"][data-value="board"]');check(`${width}: mobile destination opens viewer`,await page.locator('#viewer').count()===1);const d=await page.evaluate(()=>({w:innerWidth,s:document.documentElement.scrollWidth}));check(`${width}: viewer no page overflow`,d.s<=d.w,d);await page.locator('.board-selector summary').click();await page.screenshot({path:`${out}/after-board-menu-${width}.png`});await page.keyboard.press('Escape');await page.locator('.viewer-tabs > button[data-on-click="panel"]').click();await page.evaluate(()=>window.pending);}
 for(const width of [390,1440]){await page.setViewportSize({width,height:900});await load(`theme=light&light=${width}`);check(`${width}: light theme inherited`,await page.locator('.app.light').count()===1);await page.screenshot({path:`${out}/after-light-${width}.png`});}
 const identity=await fetch(`http://127.0.0.1:${server.port}/identity`).then(r=>r.json());
 check('root board cannot steal nested board active state',identity.nested==='nested/main.kicad_pcb',identity);
 check('schematic maps to its exact board',identity.schematic==='nested/main.kicad_pcb',identity);
 check('unlisted path keeps its own identity',identity.unlisted==='/other/main.kicad_pcb',identity);
 for(const width of [360,820,1024])for(const bot of [false,true])for(const kind of ['board','schematic','3d','mech','files','diff','review','browser']){
  await page.setViewportSize({width,height:900});await load(`view=${kind}&bot=${bot?1:0}&case=${width}`);
  check(`${width}/${bot?'bot':'thread'}/${kind}: viewer and composer fit`,await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth&&document.querySelector('.composer').getBoundingClientRect().bottom<=innerHeight+2));
  if(width>760)check(`${width}/${bot?'bot':'thread'}/${kind}: active rail item`,await page.locator(`.workspace-rail button.on[data-on-click="${kind==='mech'?'mech':kind==='files'?'fm':kind==='diff'?'diff':kind==='review'?'rv-page':'view-kind'}"]`).count()===1);
  if(['board','schematic','3d'].includes(kind))check(`${width}/${kind}: board selector only`,await page.locator('.board-selector').count()===1&&await page.locator('.viewer-bar > .board-option').count()===0);
 }
 await page.setViewportSize({width:390,height:700});await load('keyboard=sheet');await page.locator('.workspace-menu summary').click();await page.locator('.workspace-menu button').last().focus();await page.keyboard.press('Tab');check('mobile sheet wraps keyboard focus',await page.locator('.workspace-menu summary').evaluate(x=>x===document.activeElement));await page.keyboard.press('Escape');
 for(const scenario of ['empty','error'])for(const kind of scenario==='empty'?['files','mech','diff']:['3d']){await load(`view=${kind}&scenario=${scenario}`);check(`${kind}/${scenario}: fits without losing composer`,await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth&&!!document.getElementById('composer')));if(scenario==='error')check('model failure text remains visible',await page.getByText('Fixture model could not be loaded',{exact:true}).isVisible());}
 check('no browser JavaScript errors',errors.length===0,errors);
}catch(e){errors.push(String(e));check('harness completed',false,String(e));}
finally{fs.writeFileSync(`${out}/ui-qa.json`,JSON.stringify({date:new Date().toISOString(),checks,errors,limits:'Production Bend DOM and keyed patcher; local command effects discarded. No production server, physical phone, native app or helper exercised.'},null,2));await browser.close();server.stop(true)}
if(checks.some(x=>!x.ok)||errors.length)process.exitCode=1;
