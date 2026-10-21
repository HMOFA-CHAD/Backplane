'use strict';
// Called by the owner's existing authenticated Electron OR web fixture.
// Input must come from the real canonical Lr delivery/resolver fixture.
// No service/browser launch, user data access, mutation or Send here.
const assert=require('node:assert/strict'),crypto=require('node:crypto');
const hash=text=>crypto.createHash('sha256').update(text).digest('hex');
const css=value=>[...value].map(c=>'\\'+c.codePointAt(0).toString(16)+' ').join('');
async function verifyCutReportInline(page,{entryId,fullText,maxClicks=1,screenshot}){
  assert.equal(typeof entryId,'string');assert(entryId.length>0);assert.equal(typeof fullText,'string');assert([...fullText].length>1500,'Use an actually cut-short launched report');
  assert(Number.isSafeInteger(maxClicks)&&maxClicks>=1&&maxClicks<=32);
  const selector='#timeline .msg[data-id="'+css(entryId)+'"], #timeline .act[data-id="'+css(entryId)+'"]',row=page.locator(selector);
  assert.equal(await row.count(),1,'Resolve the exact report row, never a guessed source thread');
  const draft=await page.locator('#composer').inputValue();
  const navigation=()=>page.evaluate(()=>[...document.querySelectorAll('[data-on-click="select"].on,[data-on-click="bot"].on,[data-on-click="uber"].on,[data-on-click="bot-tab"].on')].map(n=>[n.getAttribute('data-on-click'),n.getAttribute('data-value')]).sort());
  const selectedBefore=await navigation(),botChat=await page.locator('[data-on-click="bot-tab"][data-value="chat"].on').count();
  const counters=()=>page.evaluate(()=>({messages:__bpPerf.trace.filter(x=>x.phase==='send'&&x.method==='view.message').length,pages:__bpPerf.trace.filter(x=>x.phase==='send'&&x.method==='view.page').length}));
  const before=await counters();let assembled='',clicks=0;const chunks=[];
  for(;clicks<maxClicks;){
    const oldLength=assembled.length;
    await row.getByRole('button',{name:clicks?'Read next part':'Read rest of message',exact:true}).click();clicks++;
    await page.waitForFunction(({selector,n})=>(document.querySelector(selector)?.querySelector('pre.thin-message-text')?.textContent.length||0)>n,{selector,n:oldLength},{timeout:10000});
    assembled=await row.locator('pre.thin-message-text').textContent();const bytes=Buffer.byteLength(assembled),delta=bytes-(chunks.at(-1)?.bytes||0);
    assert(delta>0&&delta<=8192,'Each explicit reader response stays bounded');chunks.push({bytes,delta,sha256:hash(assembled)});
    if(assembled===fullText)break;
    assert(await row.getByRole('button',{name:'Read next part',exact:true}).count(),'Backend called a still-cut-short report complete');
  }
  assert.equal(hash(assembled),hash(fullText),'Click must expose exact complete canonical report, including text beyond the 1500-character notification cut');
  assert.equal(await row.locator('[data-on-click="thin-message-more"]').count(),0,'Complete report must not keep a dead expand control');
  assert.equal(await row.locator('pre script').count(),0);assert.equal(await page.locator('#thin-result').count(),0,'Complete report stays inline');
  assert.equal(await page.locator('#composer').inputValue(),draft);
  assert.deepEqual(await navigation(),selectedBefore,'Expanding a report must retain its actual bot/ordinary conversation and chosen tab');
  assert.equal(await page.locator('[data-on-click="bot-tab"][data-value="chat"].on').count(),botChat,'Expanding a report must retain Chat');
  const after=await counters();assert.equal(after.messages-before.messages,clicks);assert.equal(after.pages,before.pages);
  if(screenshot)await page.screenshot({path:screenshot});
  return{entryId,complete:true,bytes:Buffer.byteLength(assembled),sha256:hash(assembled),clicks,chunks,draftPreserved:true,chatPreserved:true,chatKind:botChat?'bot-chat':'ordinary-thread',inline:true,messageRequests:after.messages-before.messages,historyRequests:0};
}
module.exports={verifyCutReportInline};
