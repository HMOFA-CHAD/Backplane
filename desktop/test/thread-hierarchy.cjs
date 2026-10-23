// One additive acceptance slice for thread-inspector.cjs's private fixture.
// Seed before service.start(); run in the existing Electron instance.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),assert=require('node:assert/strict');
const ids={child:'hierarchy-child',grandchild:'hierarchy-grandchild',other:'hierarchy-other',project:'hierarchy-project',history:'hierarchy-history'};

function hierarchyEvents({at,home,project,threadId='review',projectId='fixture'}){
  assert(home.startsWith(os.tmpdir()+path.sep),'only a private temporary fixture');
  const other=path.join(home,'hierarchy-project'),history=path.join(home,'legacy-history');
  fs.mkdirSync(other,{recursive:true});fs.mkdirSync(history,{recursive:true});
  const e=($,fields,time=at)=>({$,...fields,at:time});
  const t=(id,title,pid,root)=>e('ThreadCreated',{id,title,project:pid,env:'local',branch:'',worktree:root,provider:'codex',model:'gpt-6.1-sol'});
  return [e('ProjectCreated',{id:ids.project,title:'Hierarchy companion',root:other},at-10),
    t(ids.other,'Second active project',ids.project,other),
    t(ids.child,'Visible connector review',projectId,project),t(ids.grandchild,'Nested pinout check',projectId,project),
    e('ThreadParentSet',{id:ids.child,parent:threadId}),e('ThreadParentSet',{id:ids.grandchild,parent:ids.child}),
    e('SettingSet',{key:'thread.tree.'+threadId,value:'1'}),e('SettingSet',{key:'thread.tree.'+ids.child,value:'1'}),
    e('ProjectCreated',{id:'scratch',title:'Scratch',root:history},at-8640000),
    {...t(ids.history,'Retained previous conversation','scratch',history),at:at-8640000},
    e('MessagePosted',{thread:ids.history,msg:'hierarchy-preserved',role:'user',text:'Original legacy conversation identity and history preserved.'},at-8640000)];
}

async function runHierarchyAcceptance({page,home,threadId='review',child,out}){
  assert(home.startsWith(os.tmpdir()+path.sep),'never use a live profile');
  fs.mkdirSync(out,{recursive:true});
  const checks=[],created=[],running=[];
  const record=name=>{checks.push(name);fs.writeFileSync(path.join(out,'PROGRESS.json'),JSON.stringify({checks,created},null,2));};
  const log=()=>fs.readFileSync(path.join(home,'events.jsonl'),'utf8').trim().split('\n').flatMap(line=>{try{return [JSON.parse(line)];}catch{return [];}});
  const ready=async id=>page.waitForFunction(id=>document.querySelector('main')?.dataset.thread===id&&document.documentElement.dataset.backplaneRemoteReady==='true',id);
  const row=id=>page.locator('.sidebar [data-on-click="select"][data-value="'+id+'"]');
  const toggle=id=>page.locator('.sidebar button.thread-expander[data-value="'+id+'"]');
  const select=async id=>{await row(id).first().click();await ready(id);};
  const order=()=>page.locator('.sidebar section.project[data-drag-to]').evaluateAll(els=>els.map(el=>el.dataset.dragTo));
  const signal=()=>row(threadId).first().locator('.dot').getAttribute('aria-label');
  const snapshot=async name=>{const file=path.join(out,name+'.png');await page.screenshot({path:file});return file;};
  try{
    await page.setViewportSize({width:1440,height:960});await select(threadId);
    assert.equal(await row(ids.child).count(),1);assert.equal(await row(ids.grandchild).count(),1);
    assert.equal(await page.locator('.sidebar section.project[data-drag-to="scratch"]').count(),0);
    record('normal child/grandchild appear once; Scratch is absent from projects');
    const before=await order(),parentSignal=await signal();
    for(const id of [ids.child,ids.other]){
      await select(id);const composer=page.locator('textarea[data-paste="attach"]');
      await composer.fill('Private hierarchy acceptance '+id);await composer.press('Enter');
      await page.locator('.thread-workbar [data-on-click="interrupt"]').waitFor();running.push(id);
      assert.deepEqual(await order(),before,'activity must not reorder two active projects');
    }
    assert.equal(await signal(),parentSignal,'a child agent must not make its managing parent active');
    record('two captured agents run without moving projects or faking parent activity');
    for(const id of running.splice(0)){
      await select(id);await page.locator('.thread-workbar [data-on-click="interrupt"]').click();
      await page.locator('.thread-workbar [data-on-click="interrupt"]').waitFor({state:'hidden'});
    }
    await select(threadId);
    await page.locator('.subthreads-control [data-on-click="thread-child"][data-value="'+threadId+'"]').click();
    await page.waitForFunction(id=>{const now=document.querySelector('main')?.dataset.thread;return now&&now!==id&&document.documentElement.dataset.backplaneRemoteReady==='true';},threadId);
    const made=await page.locator('main').getAttribute('data-thread');created.push(made);await row(made).waitFor();
    assert.equal(await row(made).count(),1);
    const parentEvents=log().filter(e=>e.$==='ThreadParentSet'&&e.id===made);
    assert.equal(parentEvents.at(-1)?.parent,threadId,'new child keeps the selected managing thread identity');
    if(child)assert.equal(log().filter(e=>e.$==='ThreadParentSet'&&e.id===child).length,0,'delegated workers are not mass reparented');
    record('workspace creates an ordinary child with persisted true parent; delegated worker unchanged');
    await toggle(threadId).focus();await page.keyboard.press('Space');
    await page.waitForFunction(id=>document.querySelector('button.thread-expander[data-value="'+id+'"]')?.getAttribute('aria-expanded')==='false',threadId);
    assert.equal(await row(made).count(),0);
    assert(await toggle(threadId).evaluate(el=>el===document.activeElement),'collapse retains keyboard focus');
    await page.keyboard.press('Enter');await row(made).waitFor();
    assert(await toggle(threadId).evaluate(el=>el===document.activeElement));
    record('Space collapses and Enter expands without selecting another thread or losing focus');
    await page.locator('[data-on-click="thread-history"]').click();await select(ids.history);
    assert((await page.locator('main').innerText()).includes('Original legacy conversation identity and history preserved.'));
    const beforeRoute=log(),nCreated=beforeRoute.filter(e=>e.$==='ThreadCreated').length,nParent=beforeRoute.filter(e=>e.$==='ThreadParentSet').length;
    await page.locator('.subthreads-control [data-on-click="thread-child"]').click();
    await page.locator('.picker').waitFor();
    assert((await page.locator('.picker').innerText()).includes('This conversation and its history stay here.'));
    assert.equal(await page.locator('.picker [data-on-click="proj-found"],.picker [data-on-click="proj-new"],.picker [data-on-click="proj-add"]').count(),0);
    assert.equal(await page.locator('.picker .prows').innerText().then(s=>s.includes('Scratch')),false);
    await page.locator('.picker [data-on-click="proj-pick"]').first().click();await page.locator('.picker').waitFor({state:'hidden'});
    const afterRoute=log();assert.equal(afterRoute.filter(e=>e.$==='ThreadCreated').length,nCreated);assert.equal(afterRoute.filter(e=>e.$==='ThreadParentSet').length,nParent);
    assert.equal(afterRoute.filter(e=>e.$==='ThreadDeleted'&&e.id===ids.history).length,0);
    record('legacy action routes through existing project selection without creation, deletion or parent changes');
    await select(threadId);await snapshot('hierarchy-desktop');
    await page.setViewportSize({width:390,height:844});
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'390px document has no overflow');
    assert(await page.locator('.sidebar').evaluate(el=>el.scrollWidth<=el.clientWidth),'390px hierarchy has no sidebar overflow');
    await snapshot('hierarchy-mobile390');
    record('real desktop and 390px renders; no document/sidebar horizontal overflow');
    fs.writeFileSync(path.join(out,'RESULT.json'),JSON.stringify({state:'passed',checks,created,history:ids.history},null,2));
    return {checks,created,out};
  }catch(error){fs.writeFileSync(path.join(out,'FAIL.json'),JSON.stringify({state:'failed',checks,created,error:error.stack},null,2));await page.screenshot({path:path.join(out,'failure.png'),timeout:3000}).catch(()=>{});fs.writeFileSync(path.join(out,'failure.html'),await page.content().catch(()=>''));throw error;
  }finally{
    // The owning fixture shuts down its service. Only these captured stand-ins may still run.
    for(const id of running){await select(id).catch(()=>{});const stop=page.locator('.thread-workbar [data-on-click="interrupt"]');if(await stop.count())await stop.click().catch(()=>{});}
    await page.setViewportSize({width:1440,height:960});
  }
}
module.exports={hierarchyEvents,runHierarchyAcceptance,ids};
