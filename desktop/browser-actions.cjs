'use strict';
const {SNAPSHOT_SCRIPT,TEXT_SCRIPT}=require('./browser-dom.cjs');
const {targetKey}=require('./browser-wire.cjs');
const refused=message=>Object.assign(new Error(message),{dispatched:false});
const pause=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const BUTTONS={left:1,right:2,middle:4};
function normalizeURL(value){
 const raw=String(value||'').trim();if(!raw)throw refused('Browser URL required');
 if(/^[a-z][a-z0-9+.-]*:/i.test(raw)&&!/^[^/]+:\d+(\/|$)/.test(raw))return raw;
 const host=raw.startsWith('[')?raw.slice(0,raw.indexOf(']')+1):raw.split(/[/:?#]/)[0].toLowerCase();
 return (['localhost','127.0.0.1','[::1]','0.0.0.0'].includes(host)||host.endsWith('.localhost')?'http://':'https://')+raw;
}
function createBrowserActions(){
 const references=new Map(),pressed=new Map();
 return async function execute(c){
  const {op,args:a,target}=c.payload,key=targetKey(target),timeout=Math.max(1,Math.min(14000,Number(a.timeoutMs)||14000)),deadline=Date.now()+timeout;
  const status=()=>{const m=c.metadata();return{page:target.owner,url:m.url,title:m.title,loading:m.loading,tabs:c.list().map((t,index)=>({id:t.tabId,index,url:t.url,title:t.title,active:t.active})),engine:'electron'};};
  const command=async(method,params)=>{const answer=await c.command(method,params);return answer.result;};
  const evaluate=async(expression,returnByValue=true)=>{
   const reply=await command('Runtime.evaluate',{expression,returnByValue,awaitPromise:true});
   if(reply.exceptionDetails)throw Object.assign(new Error('Guest JavaScript returned an exception'),{dispatched:true});
   return returnByValue?reply.result?.value:reply.result;
  };
  async function object(){
   if(a.ref){
    const backendNodeId=references.get(key)?.get(String(a.ref));if(!backendNodeId)throw refused('Unknown or stale Browser reference; take a new snapshot');
    return (await command('DOM.resolveNode',{backendNodeId})).object?.objectId;
   }
   let selector=a.selector,locator=a.locator,role=null,text=null;
   if(locator){
    const source=String(locator);
    if(source.startsWith('css='))selector=source.slice(4);
    else if(source.startsWith('text=')){const raw=source.slice(5);text={value:raw,exact:false};if(/^(["']).*\1$/.test(raw))text={value:raw.slice(1,-1),exact:true};}
    else if(source.startsWith('role=')){
     const match=/^role=([\w-]+)(?:\[name=(?:"([^"\\]*)"|'([^'\\]*)')\])?$/.exec(source);
     if(!match)throw refused('Use role=button[name="Name"], text=Text, CSS, or a snapshot reference');
     role={name:match[1],label:match[2]??match[3]};
    }else if(!/^[a-z-]+=/.test(source))selector=source;
    else throw refused('Unsupported Browser locator engine; use a snapshot reference or CSS selector');
   }
   if(!selector&&!role&&!text)return null;
   do{
    if(role){
     const ax=await command('Accessibility.getFullAXTree',{});
     const node=(ax.nodes||[]).find(n=>!n.ignored&&n.role?.value===role.name&&(role.label===undefined||String(n.name?.value||'')===role.label)&&n.backendDOMNodeId);
     if(node)return (await command('DOM.resolveNode',{backendNodeId:node.backendDOMNodeId})).object?.objectId;
    }else{
     const expression=text?'('+function(t){
      const normalize=s=>String(s||'').replace(/\s+/g,' ').trim();
      const matches=e=>{const s=normalize(e.innerText||e.value);return t.exact?s===normalize(t.value):s.includes(normalize(t.value));};
      return [...document.querySelectorAll('body *')].find(e=>!['SCRIPT','STYLE','NOSCRIPT'].includes(e.tagName)&&e.getClientRects().length&&matches(e)&&![...e.children].some(matches))||null;
     }.toString()+')('+JSON.stringify(text)+')':'document.querySelector('+JSON.stringify(String(selector))+')';
     const value=await evaluate(expression,false);if(value?.objectId)return value.objectId;
    }
    if(Date.now()>=deadline)break;await pause(75);
   }while(true);
   throw refused('Browser target was not found');
  }
  async function useObject(fn){const id=await object();if(!id)throw refused('Browser target required');try{return await fn(id);}finally{void command('Runtime.releaseObject',{objectId:id}).catch(()=>{});}}
  async function onObject(objectId,functionDeclaration,args=[]){
   const reply=await command('Runtime.callFunctionOn',{objectId,functionDeclaration,arguments:args.map(value=>({value})),returnByValue:true,awaitPromise:true});
   if(reply.exceptionDetails)throw Object.assign(new Error('Guest target evaluation failed'),{dispatched:true});return reply.result?.value;
  }
  async function point(){
   if(a.selector||a.locator||a.ref)return useObject(id=>onObject(id,'function(){this.scrollIntoView({block:"center",inline:"center"});const r=this.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2,width:r.width,height:r.height};}'));
   if(!Number.isFinite(a.x)||!Number.isFinite(a.y))throw refused('Browser pointer coordinates required');return{x:a.x,y:a.y};
  }
  async function mouse(type,p,button='left',clickCount=1){
   if(!Object.hasOwn(BUTTONS,button)||!Number.isFinite(p.x)||!Number.isFinite(p.y))throw refused('Invalid Browser pointer input');
   let buttons=pressed.get(key)||0;if(type==='mousePressed')buttons|=BUTTONS[button];if(type==='mouseReleased')buttons&=~BUTTONS[button];
   await command('Input.dispatchMouseEvent',{type,x:p.x,y:p.y,button,buttons,clickCount});pressed.set(key,buttons);
  }
  switch(op){
   case 'status':return status();
   case 'pages':return{pages:[status()]};
   case 'open':case 'navigate':case 'goto':{
    if(!a.url&&op==='open')return status();
    const url=normalizeURL(a.url),before=c.navigation;
    if(c.grant.operations.includes('navigate'))await c.invoke('navigate',{url});else await command('Page.navigate',{url});
    await c.waitNavigation({before,readiness:a.readiness==='none'?'commit':a.readiness==='domContentLoaded'?'domContentLoaded':'load',timeoutMs:timeout});return status();
   }
   case 'back':case 'forward':case 'reload':{
    if(c.grant.operations.includes('navigate'))return c.invoke(op==='reload'?'reload':'history',op==='reload'?{}:{direction:op});
    if(op==='reload')await command('Page.reload',{});
    else{const history=await command('Page.getNavigationHistory',{}),index=history.currentIndex+(op==='back'?-1:1),entry=history.entries[index];if(!entry)throw refused('Browser history has no '+op+' entry');await command('Page.navigateToHistoryEntry',{entryId:entry.id});}
    return{target,action:op,dispatched:true,loadComplete:false};
   }
   case 'tabs':{
    if(a.selectId!==undefined||a.select!==undefined){if(a.selectId!==target.tabId)throw refused('Tab selection must carry its exact service-authorized target');await c.invoke('select',{});}
    else if(a.closeId!==undefined||a.close!==undefined){if(a.closeId!==target.tabId)throw refused('Tab close must carry its exact service-authorized target');await c.invoke('close',{});return{page:target.owner,closed:target.tabId};}
    else if(a.new!==undefined&&a.new!==false){const url=typeof a.new==='string'?a.new:a.url;if(url&&url!=='about:blank'){const before=c.navigation;if(c.grant.operations.includes('navigate'))await c.invoke('navigate',{url:normalizeURL(url)});else await command('Page.navigate',{url:normalizeURL(url)});await c.waitNavigation({before,readiness:'load',timeoutMs:timeout});}}
    const tabs=c.list();return{page:target.owner,active:tabs.findIndex(t=>t.active),tabs:tabs.map((t,index)=>({id:t.tabId,index,url:t.url,title:t.title,active:t.active}))};
   }
   case 'snapshot':{
    const page=await evaluate(SNAPSHOT_SCRIPT),ax=await command('Accessibility.getFullAXTree',{}),refs=new Map(),lines=[];
    for(const node of ax.nodes||[]){if(node.ignored)continue;const role=String(node.role?.value||''),name=String(node.name?.value||'').slice(0,300);if(!role||role==='generic')continue;
     const id=node.backendDOMNodeId;if(Number.isSafeInteger(id)&&id>0)refs.set('e'+id,id);
     lines.push('- '+role+(name?' '+JSON.stringify(name):'')+(id?' [ref=e'+id+']':''));if(lines.length>=600)break;
    }
    references.set(key,refs);const meta=c.metadata();
    let screenshot;
    if(a.screenshot){
     const capture=await command('Page.captureScreenshot',{format:'png',captureBeyondViewport:false}),metrics=await command('Page.getLayoutMetrics',{}),v=metrics.cssVisualViewport||metrics.visualViewport;
     if(typeof capture.data!=='string'||capture.data.length>700000)throw refused('Browser screenshot exceeds the private image limit; request a text snapshot');
     screenshot={mimeType:'image/png',data:capture.data,width:Math.round(v.clientWidth),height:Math.round(v.clientHeight)};
    }
    return{url:meta.url,title:meta.title,...page,outline:lines.join('\n'),console:meta.console.slice(-50),...(screenshot?{screenshot}:{})};
   }
   case 'text':{
    const full=a.selector||a.locator||a.ref?await useObject(id=>onObject(id,'function(){return this.innerText||"";}')):await evaluate(TEXT_SCRIPT);
    const text=String(full||''),max=Math.max(1,Math.min(200000,Number(a.max)||20000)),meta=c.metadata();return{url:meta.url,title:meta.title,length:text.length,truncated:text.length>max,text:text.slice(0,max)};
   }
   case 'evaluate':{
    if(typeof a.expression!=='string'||Buffer.byteLength(a.expression)>64000)throw refused('Browser expression required within64k');
    const expression=a.awaitPromise===false?'(()=>{const v=('+a.expression+');return v instanceof Promise?"[Promise]":v;})()':a.expression;
    const value=await evaluate(expression),json=JSON.stringify(value??null);return json.length>64000?{truncated:true,json:json.slice(0,64000)}:value??null;
   }
   case 'click':{
    const p=await point(),button=a.button||'left',count=Number(a.clickCount)||1;if(count<1||count>3)throw refused('Invalid Browser click count');
    await mouse('mouseMoved',p,button,0);for(let n=1;n<=count;n++){await mouse('mousePressed',p,button,n);await mouse('mouseReleased',p,button,n);}return{};
   }
   case 'mouse':{
    const p=await point(),type={move:'mouseMoved',down:'mousePressed',up:'mouseReleased'}[a.type];if(!type)throw refused('Mouse type must be move/down/up');await mouse(type,p,a.button||'left',a.type==='move'?0:1);return{};
   }
   case 'type':{
    if(a.selector||a.locator||a.ref)await useObject(id=>onObject(id,'function(clear){this.focus();if(clear){if(this.select)this.select();else{const r=document.createRange();r.selectNodeContents(this);const s=getSelection();s.removeAllRanges();s.addRange(r);}}}',[a.clear===true]));
    else if(a.clear)await evaluate('(()=>{const e=document.activeElement;if(e&&e.select)e.select();})()');
    await command('Input.insertText',{text:String(a.text??'')});return{};
   }
   case 'press':{
    const bits=String(a.key||'').split('+'),keyName=bits.pop(),mods=[...(Array.isArray(a.modifiers)?a.modifiers:[]),...bits].map(m=>m==='ControlOrMeta'?(process.platform==='darwin'?'Meta':'Control'):m);
    if(!keyName||mods.some(m=>!['Control','Meta','Alt','Shift'].includes(m)))throw refused('Unsupported Browser key');
    if(mods.some(m=>m==='Control'||m==='Meta')&&/^[cvx]$/i.test(keyName))throw refused('Agent OS clipboard shortcuts require separate authorization');
    const modifiers=mods.reduce((v,m)=>v|({Alt:1,Control:2,Meta:4,Shift:8}[m]),0),virtual={Enter:13,Tab:9,Escape:27,Backspace:8,Delete:46,ArrowLeft:37,ArrowUp:38,ArrowRight:39,ArrowDown:40,Home:36,End:35,PageUp:33,PageDown:34};
    if(keyName.length===1&&!modifiers){await command('Input.insertText',{text:keyName});return{};}
    const windowsVirtualKeyCode=virtual[keyName]??(keyName.length===1?keyName.toUpperCase().charCodeAt(0):0);if(!windowsVirtualKeyCode)throw refused('Unsupported Browser key');
    const params={key:keyName,modifiers,windowsVirtualKeyCode};
    await command('Input.dispatchKeyEvent',{type:'keyDown',...params,...(keyName==='Enter'?{text:'\r',unmodifiedText:'\r'}:{})});
    await command('Input.dispatchKeyEvent',{type:'keyUp',...params});return{};
   }
   case 'scroll':{
    const dx=Number(a.dx??a.deltaX??0),dy=Number(a.dy??a.deltaY??0);if(!Number.isFinite(dx)||!Number.isFinite(dy))throw refused('Invalid Browser wheel delta');
    if(a.selector||a.locator||a.ref)await useObject(id=>onObject(id,'function(dx,dy){this.scrollBy(dx,dy);}',[dx,dy]));
    else{const view=await command('Page.getLayoutMetrics',{}),v=view.cssVisualViewport||view.visualViewport;await command('Input.dispatchMouseEvent',{type:'mouseWheel',x:Number.isFinite(a.x)?a.x:v.clientWidth/2,y:Number.isFinite(a.y)?a.y:v.clientHeight/2,deltaX:dx,deltaY:dy});}return{};
   }
   case 'select':{
    const selection=Object.fromEntries(['values','value','label','index'].filter(name=>Object.hasOwn(a,name)).map(name=>[name,a[name]]));
    const selected=await useObject(id=>onObject(id,'function(a){if(this.tagName!=="SELECT")throw Error("target is not a select");const values=Array.isArray(a.values)?a.values.map(String):a.value!==undefined?[String(a.value)]:null;for(let i=0;i<this.options.length;i++){const o=this.options[i];o.selected=values?values.includes(o.value):a.label!==undefined?o.label===String(a.label):i===a.index;}this.dispatchEvent(new Event("input",{bubbles:true}));this.dispatchEvent(new Event("change",{bubbles:true}));return Array.from(this.selectedOptions,o=>o.value);}',[selection]));return{selected};
   }
   case 'wait_for':{
    if(!a.selector&&!a.locator&&!a.ref&&!a.text&&!a.url&&!a.urlIncludes)throw refused('Browser wait condition required');
    const start=Date.now();do{let ok=true;if(a.selector||a.locator||a.ref)await useObject(id=>onObject(id,'function(){const r=this.getBoundingClientRect();return r.width>0&&r.height>0;}')).then(value=>{ok=!!value;});
     if(a.text)ok=ok&&await evaluate('(document.body?.innerText||"").includes('+JSON.stringify(String(a.text))+')');
     if(a.url||a.urlIncludes)ok=ok&&await evaluate('location.href.includes('+JSON.stringify(String(a.url||a.urlIncludes))+')');
     if(ok)return{};await pause(75);
    }while(Date.now()-start<timeout);throw refused('Browser wait condition not met');
   }
   case 'record':return c.record(a.on===true);
   case 'console':return{entries:c.metadata().console};
   case 'close_page':await c.invoke('close',{});return{page:target.owner,closed:target.tabId};
   default:throw refused('Browser operation '+op+' has no authorized direct-guest adapter yet');
  }
 };
}
module.exports={createBrowserActions};
