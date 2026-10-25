// Run once by the integrator with the emitted test/bub_move_test.bend module.
// All browser windows are headless, isolated profiles; no hub or real lease.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import { pathToFileURL } from 'node:url';
import { BubMoveObserver } from '../../src/web/bub-move.js';

const F = (await import(pathToFileURL(path.resolve(process.argv[2])).href)).default;
const sample = JSON.parse(F.sample());
const compare = (a, b) => JSON.parse(F.move(JSON.stringify(a), JSON.stringify(b)));
const lease = (holder, term, stamp = String(term), uid = 'bub') => ({ uid, holder, term: String(term), stamp, name: holder, look: 0 });
const checks = [];
const check = (name, condition) => { checks.push({name, ok: !!condition});assert.ok(condition, name);console.log('ok ' + name); };
const observer = new BubMoveObserver(compare);
const a = lease('desktop', 1), b = lease('Boat', 2), c = lease('desktop', 3);
check('initial live observation is quiet', observer.observe('desktop-link', a) === null);
check('second paired hub baseline is quiet', observer.observe('boat-link', a) === null);
check('live committed move announces', observer.observe('desktop-link', b)?.changed === true);
check('same move on paired hub dedupes', observer.observe('boat-link', b) === null);
observer.disconnect('desktop-link');
check('rejoin with changed lease is quiet', observer.observe('desktop-link', c) === null);
check('continuous other hub can still announce that move', observer.observe('boat-link', c)?.changed === true);
check('stale replica cannot replay older move', observer.observe('boat-link', b) === null);
check('new uid is quiet', observer.observe('boat-link', lease('Boat', 4, '004', 'new-bub')) === null);
check('empty holder resets baseline', observer.observe('boat-link', lease('', 5, '005', 'new-bub')) === null);
check('first holder after missing lease is quiet', observer.observe('boat-link', lease('desktop', 6, '006', 'new-bub')) === null);
check('same-term newer stamp announces', observer.observe('boat-link', lease('Boat', 6, '007', 'new-bub'))?.changed === true);
check('static generated cat and rig', !sample.cat.includes('animate') && sample.rig.every(p => p.anims.length === 0));
check('lifetime is two seconds', sample.duration === 2000);

const out = path.resolve(process.env.BUB_MOVE_OUT || 'build/bub-move');
fs.mkdirSync(out, { recursive: true });
const moduleText = fs.readFileSync('src/web/bub-move.js', 'utf8');
const styles = fs.readFileSync('src/web/style.css', 'utf8');
const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (url.pathname === '/move.js') { res.setHeader('Content-Type', 'text/javascript');return res.end(moduleText); }
  if (url.pathname === '/style.css') { res.setHeader('Content-Type', 'text/css');return res.end(styles); }
  res.setHeader('Content-Type', 'text/html');
  res.end(`<!doctype html><html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><link rel="stylesheet" href="/style.css"><body>
    <div class="app" style="display:block;height:100dvh;padding:160px 12px 12px;box-sizing:border-box">
      <textarea id="draft" style="box-sizing:border-box;width:100%;height:90px">Unsent draft — keep my selection</textarea>
      <button id="stop">Stop</button><button id="answer">Allow once</button>
      <button id="under" style="position:fixed;top:28px;left:calc(50% - 30px);width:60px;height:60px">Keep typing</button>
    </div><script type="module">
      import {showBubMove} from '/move.js';
      window.clicks=[];document.addEventListener('click', e=>{if(e.target.tagName==='BUTTON')window.clicks.push(e.target.id)});
      window.show=move=>showBubMove(move);window.fixtureReady=true;
    </script></body></html>`);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const { chromium } = await import(pathToFileURL(process.env.BACKPLANE_PLAYWRIGHT_PATH || path.resolve('tools/browser/node_modules/playwright-core/index.mjs')).href);
const browser = await chromium.launch({ headless: true, ...(process.env.BACKPLANE_CHROME ? { executablePath: process.env.BACKPLANE_CHROME } : {}), args: ['--disable-dev-shm-usage'] });
const errors = [];
try {
  for (const [width, height, theme, reduced] of [[1440,900,'dark',false],[360,740,'dark',false],[320,600,'light',false],[390,740,'light',true]]) {
    const context = await browser.newContext({ viewport: { width, height }, reducedMotion: reduced ? 'reduce' : 'no-preference' });
    const page = await context.newPage();page.setDefaultTimeout(5000);page.on('pageerror', e => errors.push(String(e)));
    await page.goto(`http://127.0.0.1:${server.address().port}/`);await page.waitForFunction(() => window.fixtureReady);
    await page.evaluate(theme => document.documentElement.classList.toggle('light', theme === 'light'), theme);
    await page.locator('#draft').focus();
    await page.evaluate(() => { window.draft = document.getElementById('draft');draft.setSelectionRange(3, 12);draft.dispatchEvent(new CompositionEvent('compositionstart', {data:'入力',bubbles:true})); });
    await page.evaluate(move => window.show(move), sample);
    const tag = `${width}-${theme}-${reduced?'reduced':'hop'}`;
    check(tag + ' focus, node, draft and selection retained', await page.evaluate(() => document.activeElement === draft && draft === document.getElementById('draft') && draft.value === 'Unsent draft — keep my selection' && draft.selectionStart === 3 && draft.selectionEnd === 12));
    await page.locator('#under').click();
    await page.locator('#answer').click();await page.locator('#stop').click();
    check(tag + ' pointer reaches underlying controls', await page.evaluate(() => ['under','answer','stop'].every(id => window.clicks.includes(id))));
    check(tag + ' bounded, no horizontal or document escape', await page.evaluate(() => {
      const b=document.getElementById('bub-move').getBoundingClientRect();
      return b.left>=0 && b.right<=innerWidth && b.top>=0 && b.bottom<=innerHeight && document.documentElement.scrollWidth<=innerWidth && document.documentElement.scrollHeight<=innerHeight;
    }));
    check(tag + ' no focusable descendants', await page.locator('#bub-move :is(button,input,textarea,a,[tabindex])').count() === 0);
    check(tag + ' reduced motion has no hopping animation', !reduced || await page.locator('.bub-move-cat').evaluate(cat => getComputedStyle(cat).animationName === 'none'));
    // Pause only for a deterministic receipt; the actual removal timer runs.
    await page.locator('#bub-move').evaluate(toast => toast.getAnimations({subtree:true}).forEach(a => { a.pause();a.currentTime=750; }));
    await page.screenshot({ path: path.join(out, `bub-move-${tag}.png`) });
    await page.locator('#bub-move').waitFor({state:'detached', timeout:2500});
    check(tag + ' dismissed automatically', await page.locator('#bub-move').count() === 0);
    await page.evaluate(() => draft.dispatchEvent(new CompositionEvent('compositionend', {data:'入力',bubbles:true})));
    await context.close();
  }
  check('no browser errors', errors.length === 0);
} finally {
  fs.writeFileSync(path.join(out, 'RECEIPT.json'), JSON.stringify({kind:'isolated production presentation fixture; not a real home move', checks, errors, sourceModule:'src/web/bub-move.js', pureProjection:'src/core/bub-move.bend', styles:'src/web/style.css'}, null, 2));
  await browser.close();await new Promise(resolve => server.close(resolve));
}
