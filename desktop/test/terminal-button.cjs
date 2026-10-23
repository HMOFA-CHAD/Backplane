// One real desktop button check; generated home, blocked providers, no live data.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os'), assert = require('node:assert/strict');
const { _electron } = require('playwright-core');
const { Service } = require('../service.cjs');
const stage = path.resolve(process.env.BACKPLANE_LOCAL_STAGE);
const info = JSON.parse(fs.readFileSync(path.join(stage, 'LOCAL.json')));
const out = process.env.TERMINAL_OUT || path.join(stage, 'terminal-button-' + Date.now());
fs.mkdirSync(out, { recursive: true });
const baseline = process.env.TERMINAL_BASELINE === '1';
const missing = process.env.TERMINAL_MISSING_SHELL === '1';
const workspace = process.env.TERMINAL_WORKSPACE === '1';
const home = fs.mkdtempSync(path.join(os.tmpdir(), 'backplane-terminal-check-'));
const project = path.join(home, 'project root'), cwd = path.join(project, "thread's worktree");
fs.mkdirSync(cwd, { recursive: true });
const agents = path.join(home, 'agents'); fs.mkdirSync(agents);
for (const name of ['claude', 'codex', 'grok', 'muse', 'agy', 'opencode']) fs.writeFileSync(path.join(agents, name), '#!/bin/sh\nexit 127\n', { mode: 0o755 });
const at = Math.floor(Date.now() / 1000), thread = 'terminal-fixture';
const ev = ($, fields) => ({ $, ...fields, at });
const events = [ev('ProjectCreated', { id: 'fixture', title: 'Terminal fixture', root: project }),
  ev('ThreadCreated', { id: thread, title: 'Terminal button acceptance', project: 'fixture', env: 'local', branch: '', worktree: cwd, provider: 'codex', model: '' }),
  ...['restart.continue', 'mail.on', 'telemetry.share'].map(key => ev('SettingSet', { key, value: 'off' })),
  ev('SettingSet', { key: 'onboard.done', value: '1' }), ev('MessagePosted', { thread, msg: 'hello', role: 'assistant', text: 'Terminal fixture ready.' })];
if (workspace) events.push(
  ev('ThreadCreated', { id: 'fixture-next', title: 'Second terminal fixture', project: 'fixture', env: 'local', branch: '', worktree: project, provider: 'codex', model: '' }),
  ev('MessagePosted', { thread: 'fixture-next', msg: 'next-hello', role: 'assistant', text: 'Second fixture ready.' }),
  ev('ProjectCreated', { id: 'other-project', title: 'Other navigation project', root: project }),
  ev('ThreadCreated', { id: 'other-thread', title: 'Other project thread', project: 'other-project', env: 'local', branch: '', worktree: project, provider: 'codex', model: '' }),
  ev('ThreadCreated', { id: 'bub-thread', title: 'Fixture Bub chat', project: 'fixture', env: 'local', branch: '', worktree: project, provider: 'codex', model: '' }),
  ev('BotSet', { id: 'bub', name: 'Bub', thread: 'bub-thread', look: 306440, persona: '' }), ev('UberSet', { bot: 'bub', uid: 'terminal-fixture-uber' }));
fs.writeFileSync(path.join(home, 'events.jsonl'), events.map(JSON.stringify).join('\n') + '\n');
const env = { ...process.env, BACKPLANE_AGENTS: agents, BACKPLANE_COPY: '1', BACKPLANE_NO_UPDATE: '1', BACKPLANE_TELEMETRY: 'off',
  BACKPLANE_PEERS: '', BACKPLANE_LOCK_DIR: path.join(home, 'locks'), SHELL: missing ? '/missing/backplane-fixture-shell' : '/bin/sh' };
Object.assign(process.env, env);
const binary = path.join(stage, 'payload/backplane-serve'), web = path.join(stage, 'payload/web');
const service = new Service({ home, binary, web, expectedVersion: info.version });
const quote = s => "'" + s.replaceAll("'", "'\\''") + "'";
const prefix = { mode: missing ? 'missing-shell' : baseline ? 'baseline-output-dropped' : workspace ? 'workspace-keyboard-floating-terminal' : 'terminal-button',
  stage, source: info.commit, version: info.version, cwd, project, home, shell: env.SHELL, automation: 'off', telemetry: 'off' };
fs.writeFileSync(path.join(out, 'START.json'), JSON.stringify(prefix, null, 2));
console.log(JSON.stringify({ state: 'started', ...prefix }));
let app, page, step = 'service-start'; const errors = [], wire = [];
// Decode synthetic-fixture frames using the product codec; retain only state
// metadata. No command text, terminal bytes, transcript, headers or auth.
async function captureWorkspaceState(page) {
  const { cbor, plain } = await import('../../src/web/wire.js');
  const source = fs.readFileSync(path.join(__dirname, '../../src/core/cbor.bend'), 'utf8');
  const dict = name => JSON.parse(new RegExp('def Cbor\\.' + name + '\\(\\) -> List<&2, String>:\\s*(\\[[\\s\\S]*?\\])\\n').exec(source)[1]);
  const keys = dict('keys'), words = dict('words'), cdp = await page.context().newCDPSession(page);
  const record = (direction, event) => {
    if (wire.length >= 160) return;
    try {
      const frame = event.response;
      const o = frame.opcode === 2 ? plain(cbor(Buffer.from(frame.payloadData, 'base64'), keys, words)) : JSON.parse(frame.payloadData);
      if (!o || !['view.open','view.action','view.update','term.open','term.resize','term.input'].includes(o.m) && !['reply','view.changed'].includes(o.t)) return;
      const p = o.p || {}, r = o.result || {}, session = p.session || r.session;
      let panels = 0, inputs = 0;
      const visit = n => { if (!n || typeof n !== 'object') return; if(n.key === 'floating-terminal')panels++;if(n.key === 'term')inputs++;for(const kid of n.kids || [])visit(kid); };
      visit(r.shown);
      wire.push({ direction, id:o.id, type:o.t, method:o.m, action:p.action,
        requestRevision:p.requestRevision ?? r.requestRevision, viewRevision:o.viewRevision ?? r.viewRevision,
        term:session?.open?.term, palette:session?.open?.palette, ownerPresent:!!session?.drafts?.['@terminal.owner'],
        panels, inputs, nextTarget:!!r.nextTarget, ok:o.ok,
        methods:(r.cmds || []).filter(c => c.type === 'send').map(c => { try { return JSON.parse(c.text).m; } catch { return 'invalid'; } }) });
    } catch { wire.push({direction,decodeFailed:true}); }
  };
  cdp.on('Network.webSocketFrameSent', e => record('sent', e));
  cdp.on('Network.webSocketFrameReceived', e => record('received', e));
  await cdp.send('Network.enable');
}
(async () => { try {
  await service.start();
  step = 'desktop-start';
  app = await _electron.launch({ executablePath: path.join(stage, 'desktop/runtime/backplane-desktop'), args: [],
    env: { ...env, BACKPLANE_HOME: home, BACKPLANE_SERVICE: binary, BACKPLANE_WEB: web, BACKPLANE_SERVICE_VERSION: info.version, DISPLAY: env.DISPLAY || ':0' } });
  page = await app.firstWindow();
  page.setDefaultTimeout(12000);
  await captureWorkspaceState(page);
  page.on('pageerror', e => errors.push(e.message));
  step = 'initial-ready';
  await page.waitForFunction(() => document.documentElement.dataset.backplaneRemoteReady === 'true');
  const skip = page.locator('[data-on-click="ob-skip"]');
  if (await skip.count()) await skip.click();
  step = 'select-fixture';
  await page.locator(`[data-on-click="select"][data-value="${thread}"]`).first().click();
  await page.locator('[data-id="hello"]').waitFor();
  step = 'open-terminal-button';
  await page.locator('[data-on-click="term-toggle"]').first().click();
  await page.locator('#term').waitFor();
  step = missing ? 'missing-shell-message' : 'shell-command';
  if (missing) {
    await page.waitForFunction(() => document.querySelector('.term-pane')?.textContent.includes('Check SHELL'));
    const text = await page.locator('.term-pane').innerText();
    assert(text.includes(env.SHELL)); assert(text.includes(cwd));
  } else {
    // Octal output cannot be confused with the shell echoing the command.
    const marker = 'BACKPLANE_TERMINAL_OK';
    const octal = [...marker].map(c => '\\' + c.charCodeAt(0).toString(8).padStart(3, '0')).join('');
    const receipt = path.join(home, 'cwd-receipt');
    const wrote = new Promise((resolve, reject) => {
      const timer = setTimeout(() => { watch.close(); reject(Error('Terminal command did not run')); }, 10000);
      const watch = fs.watch(home, (_event, file) => { if (file === 'cwd-receipt' && fs.existsSync(receipt) && fs.readFileSync(receipt, 'utf8') === cwd) { clearTimeout(timer);watch.close();resolve(); } });
    });
    await page.locator('#term').focus();
    await page.keyboard.insertText(`printf '%s' "$PWD" > ${quote(receipt)}; printf '${octal}\\n'; pwd`);
    await page.keyboard.press('Enter');
    await wrote;
    if (baseline) assert(!(await page.locator('.term-pane').innerText()).includes(marker), 'baseline discards actual PTY output');
    else {
      await page.waitForFunction(marker => document.querySelector('.term-pane')?.textContent.includes(marker), marker);
      assert((await page.locator('.term-pane').innerText()).includes(cwd));
      step = 'hide-reopen-terminal';
      const hide = page.locator('.floating-terminal [data-on-click="ws-term-hide"]');
      if (await hide.count()) await hide.click();
      else await page.locator('.term-pane [data-on-click="term-toggle"]').click();
      await page.locator('#term').waitFor({ state: 'detached' });
      await page.locator('[data-on-click="term-toggle"]').first().click();
      await page.waitForFunction(marker => document.querySelector('.term-pane')?.textContent.includes(marker), marker);
      if (workspace) {
        step = 'workspace-session-navigation';
        // The new panel stays attached to the same real shell across navigation.
        const shell = page.locator('#term');
        await shell.focus(); await page.keyboard.insertText("BP_TERMINAL_SESSION='same shell'; printf '\\123\\105\\124\\137\\117\\113\\n'"); await page.keyboard.press('Enter');
        await page.waitForFunction(() => document.querySelector('.term-pane')?.textContent.includes('SET_OK'));
        await page.keyboard.insertText('sleep 30');await page.keyboard.press('Enter');
        await page.keyboard.press('Control+c');
        await page.locator('[data-on-click="select"][data-value="fixture-next"]').first().click();
        await page.locator('[data-id="next-hello"]').waitFor();
        assert.equal(await page.locator('.floating-terminal').getAttribute('data-terminal-owner'), thread);
        await shell.focus();
        const retained = 'SESSION_RETAINED_OK', encoded = [...retained].map(c => '\\' + c.charCodeAt(0).toString(8)).join('');
        await page.keyboard.insertText(`test "$BP_TERMINAL_SESSION" = 'same shell' && printf '${encoded}\\n'`); await page.keyboard.press('Enter');
        await page.waitForFunction(text => document.querySelector('.term-pane')?.textContent.includes(text), retained);
        step = 'workspace-pty-resize';
        const oldRows = await page.locator('.term-pane .tl').count();
        await page.locator('.floating-terminal').evaluate(el => { el.style.width = '620px';el.style.height = '320px'; });
        await page.waitForFunction(rows => document.querySelectorAll('.term-pane .tl').length < rows, oldRows);
        const sizeFile = path.join(home, 'pty-size');
        const resized = new Promise((resolve, reject) => {
          const timer = setTimeout(() => { watcher.close();reject(Error('PTY size receipt missing')); }, 10000);
          const watcher = fs.watch(home, (_event, file) => { if (file === 'pty-size' && fs.existsSync(sizeFile) && /^\d+ \d+\s*$/.test(fs.readFileSync(sizeFile, 'utf8'))) { clearTimeout(timer);watcher.close();resolve(fs.readFileSync(sizeFile, 'utf8').trim().split(/\s+/).map(Number)); } });
        });
        await shell.focus();await page.keyboard.insertText(`stty size > ${quote(sizeFile)}`);await page.keyboard.press('Enter');
        const [rows, cols] = await resized;assert.equal(rows, await page.locator('.term-pane .tl').count());assert(cols >= 20);
        await page.screenshot({ path: path.join(out, 'floating-terminal.png') });
        // Ordinary nav is ignored in editors; command entry is explicit.
        step = 'workspace-keyboard-palette';
        const composer = page.locator('.composer textarea').first();await composer.fill('Fixture draft kept');await page.keyboard.press('Control+1');
        assert.equal(await page.locator('main[data-thread]').getAttribute('data-thread'), 'fixture-next');
        assert.equal(await composer.inputValue(), 'Fixture draft kept');
        await page.keyboard.press('Control+Shift+P');await page.locator('#workspace-query').waitFor();
        await page.locator('#workspace-query').fill('Delete thread');await page.keyboard.press('Enter');
        await page.locator('[data-on-click="delete-no"]').waitFor();await page.locator('[data-on-click="delete-no"]').click();
        // Restore exact prior sidebar order, rather than assuming recency.
        const ids = await page.locator('.sidebar section.project[data-drag-to="fixture"] [data-on-click="select"]').evaluateAll(xs => xs.map(x => x.getAttribute('data-value')));
        assert(ids.length >= 2);
        await page.locator(`[data-on-click="select"][data-value="${ids[0]}"]`).first().click();
        const blur = () => page.locator('textarea:focus,input:focus').evaluateAll(xs => xs.forEach(el => el.blur()));
        await blur();await page.keyboard.press('Control+Shift+]');
        await page.waitForFunction(id => document.querySelector('main[data-thread]')?.dataset.thread === id, ids[1]);
        await blur();await page.keyboard.press('Control+Shift+[');
        await page.waitForFunction(id => document.querySelector('main[data-thread]')?.dataset.thread === id, ids[0]);
        await blur();await page.keyboard.press('Control+2');
        await page.waitForFunction(id => document.querySelector('main[data-thread]')?.dataset.thread === id, ids[1]);
        const firstProjectIds = await page.locator('.sidebar section.project').first().locator('[data-on-click="select"]').evaluateAll(xs => xs.map(x => x.getAttribute('data-value')));
        const firstProjectThread = firstProjectIds.includes(ids[1]) ? ids[1] : firstProjectIds[0];
        await blur();await page.keyboard.press('Alt+1');
        await page.waitForFunction(id => document.querySelector('main[data-thread]')?.dataset.thread === id, firstProjectThread);
        await blur();await page.keyboard.press('Control+Shift+U');
        await page.locator('.bot-tabs [data-value="chat"].on').waitFor();
        await page.locator(`[data-on-click="select"][data-value="${thread}"]`).first().click();await page.locator('[data-id="hello"]').waitFor();
        await blur();await page.keyboard.press('Meta+`');await page.locator('#term').waitFor({ state: 'detached' });
        await page.keyboard.press('Meta+`');await page.locator('#term').waitFor();
        await page.keyboard.press('Control+Shift+P');await page.locator('#workspace-query').waitFor();
        await page.locator('#workspace-query').fill('Browser');await page.waitForFunction(() => document.querySelectorAll('.workspace-command').length === 1);
        await page.screenshot({ path: path.join(out, 'workspace-palette.png') });
        await page.keyboard.press('Escape');
      }
    }
  }
  fs.writeFileSync(path.join(out, 'WIRE-STATE.json'), JSON.stringify(wire, null, 2));
  await page.screenshot({ path: path.join(out, 'terminal.png') });
  assert.deepEqual(errors, []);
  const result = { state: 'passed', mode: missing ? 'missing-shell' : baseline ? 'baseline-output-dropped' : workspace ? 'workspace-keyboard-floating-terminal' : 'terminal-button', stage, source: info.commit,
    version: info.version, cwd, project, home, errors, automation: 'off', telemetry: 'off' };
  fs.writeFileSync(path.join(out, 'RESULT.json'), JSON.stringify(result, null, 2)); console.log(JSON.stringify(result));
} catch (error) {
  console.error(error); process.exitCode = 1;
  fs.writeFileSync(path.join(out, 'WIRE-STATE.json'), JSON.stringify(wire, null, 2));
  // Structural evidence only: never copy terminal text, commands, tokens or full DOM.
  const display = page ? await page.evaluate(() => ({
    mode: document.documentElement.dataset.backplaneMode,
    ready: document.documentElement.dataset.backplaneRemoteReady,
    selected: document.querySelector('main[data-thread]')?.dataset.thread,
    workspaceRoots: document.querySelectorAll('.workspace-root').length,
    panels: [...document.querySelectorAll('.floating-terminal')].map(el => ({
      owner: el.dataset.terminalOwner, connected: el.isConnected,
      rect: (() => { const r = el.getBoundingClientRect();return { x:r.x,y:r.y,width:r.width,height:r.height }; })(),
      visibility: getComputedStyle(el).visibility, display: getComputedStyle(el).display
    })),
    terminalInputs: document.querySelectorAll('#term').length,
    terminalButton: [...document.querySelectorAll('[data-on-click="term-toggle"]')].map(el => ({ tag:el.tagName, classes:el.className })),
    palette: !!document.querySelector('#workspace-query')
  })).catch(() => null) : null;
  fs.writeFileSync(path.join(out, 'FAIL.json'), JSON.stringify({ state:'failed', ...prefix, step, error: { name:error.name, message:error.message }, errors, display }, null, 2));
  if (page) await page.screenshot({ path: path.join(out, 'failure.png'), timeout: 3000 }).catch(() => {});
} finally { if (app) await app.close(); service.stop(); } })();
