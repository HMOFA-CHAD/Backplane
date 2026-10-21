import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import vm from 'node:vm';
import {encode} from './ios_test_cbor';
import {cbor, plain} from '../../src/web/wire.js';

const [bridge, report] = process.argv.slice(2);
const source = readFileSync(bridge, 'utf8');
const A = 'a:3787', B = 'b:3787', conv = 'pair:a|b';
let checks = 0;
function check(value: unknown, label: string) { assert.ok(value, label); checks++; }
function equal(actual: unknown, expected: unknown, label: string) { assert.deepEqual(actual, expected, label); checks++; }
function setup() {
  let now = 1_800_000_000_000;
  class Clock extends Date { static now() { return now; } }
  const box: any = {console, Date: Clock};
  vm.runInNewContext(source, box);
  const app = box.Backplane;
  const metadata = JSON.parse(app.headerKeys());
  const wires = (out: any) => out.cmds.filter((c: any) => c.type === 'send').map((c: any) => ({hub: c.hub, ...plain(cbor(new Uint8Array(Buffer.from(c.data, 'base64')), metadata.keys, metadata.words))}));
  function recv(hub: string, data: any) {
    const bytes: number[] = []; encode(data, bytes);
    return JSON.parse(app.recv(hub, Buffer.from(bytes).toString('base64'), false, false));
  }
  const act = (action: string, value: string, quiet = false) => JSON.parse(app[quiet ? 'quiet' : 'act'](action, value));
  const envelope = (hub: string, action: string, value = '', extra = {}) => JSON.stringify({hub, owner: 'b1', conversation: conv, action, value, recipient: 'thread:bt1', draft: 'captured 日本語', ...extra});
  const mail = (hub: string, action: string, value = '', quiet = false, extra = {}) => act('mailroom-action', envelope(hub, action, value, extra), quiet);
  app.start('phone', '{}'); app.hubs([A, B]); app.local('mailroom-renderer', 'ios-v1');
  for (const hub of [A, B]) {
    app.online(hub, true, true);
    recv(hub, {t: 'log', origin: 'origin-' + hub, items: [
      {$: 'ThreadCreated', id: 'bt1', project: '', title: 'Kit', env: 'local', branch: '', worktree: '', provider: 'claude', model: '', at: 100},
      {$: 'BotSet', id: 'b1', name: 'Kit ' + hub, thread: 'bt1', look: 7, persona: 'helps', at: 101},
      {$: 'ConvSet', id: conv, subject: 'Exact conversation', kind: 'pair', parts: 'person\nbot:b1\nthread:bt1', project: '', tags: '', at: 102},
      {$: 'MailPosted', id: 'seed', conv, from: 'bot:b1', to: 'person', kind: 'thread', ref: '', want: 'fyi', head: 'Ready', size: 5, at: 103},
    ]});
    act('bot', hub + '|b1');
    const opened = act('bot-tab', 'mail');
    for (const r of wires(opened).filter((r: any) => r.m === 'mail.list')) recv(hub, {t: 'reply', id: r.id, ok: true, result: {convs: [{id: conv, subject: 'Exact conversation', head: 'Ready', last: 103}], total: 1}});
    const reading = act('mail-open', conv);
    const request = wires(reading).find((r: any) => r.m === 'mail.read');
    check(request, 'canonical conversation requests complete bodies ' + hub);
    recv(hub, {t: 'reply', id: request.id, ok: true, result: {conv: {id: conv, subject: 'Exact conversation', parts: ['person', 'bot:b1', 'thread:bt1']}, mails: [{id: 'raw|stable', from: 'bot:b1', text: 'Complete body 日本語', at: 103}], more: false}});
    mail(hub, 'mail-to', 'thread:bt1');
    mail(hub, 'bfield', 'mrreply\x1fretained local draft', true);
  }
  const screen = () => JSON.parse(app.screen()).screen;
  function select(hub: string) { act('bot', hub + '|b1'); act('bot-tab', 'mail'); }
  function startRecent(hub: string) {
    const savedBot = screen().bot;
    const request = wires(recv(hub, {t: 'mobile', generation: 'g1'})).find((r: any) => r.m === 'mobile.screen');
    check(request, 'real recent request exists');
    const session = structuredClone(request.p.session);
    check(!Object.keys(session.drafts).some(k => k.startsWith('@mr.') || k.startsWith('@f.mr')), 'mail scratch excluded from presentation request');
    session.drafts['@f.mrreply'] = 'forged older draft';
    session.drafts['@mr.send.state'] = 'accepted';
    session.drafts['@mr.mobile.anchor'] = 'forged anchor';
    // Older server schema: a real bot header, no Mailroom projection/capability.
    const oldBot = {...savedBot, tab: 'chat', tabs: [{id: 'chat', label: 'Chat'}]};
    delete oldBot.mailroom; delete oldBot.mailroomLoading;
    const answer = recv(hub, {t: 'reply', id: request.id, ok: true, result: {mobile: 1, session, shown: {key: hub, name: hub, j: {bot: oldBot}}, cmds: []}});
    equal(answer.screen.bot.mailroomLoading, true, 'old server header visibly waits for canonical history');
    equal(answer.screen.bot.mailroom, null, 'old presentation cannot forge a Mailroom body');
    equal(answer.screen.bot.tabs.filter((t: any) => t.id === 'mail').length, 1, 'exactly one visible Mailroom tab');
    return request;
  }
  return {app, wires, recv, act, mail, screen, select, startRecent, advance: () => { now += 6001; }};
}

for (const end of ['history', 'timeout', 'disconnect', 'generation']) {
  const t = setup(); t.select(B);
  check(t.screen().bot?.mailroom?.body, 'canonical fixture body absent: ' + JSON.stringify(t.screen().bot));
  equal(t.screen().bot.mailroom.body.messages[0].id, 'raw|stable', 'actual canonical typed cache loaded');
  t.startRecent(B);
  const blocked = [
    ['mailroom-action', JSON.stringify({hub: B, owner: 'b1', conversation: conv, action: 'mail-send', value: '', recipient: 'thread:bt1', draft: 'MUST NOT QUEUE'})],
    ['mail-send', ''], ['mail-open', conv], ['bot-tab', 'mail'], ['bfield', 'mrreply\x1fMUST NOT ADOPT'],
  ];
  for (const [action, value] of blocked) for (const quiet of [false, true]) {
    const out = t.act(action, value, quiet);
    equal(t.wires(out).length, 0, 'no wire command or queued presentation for ' + action + '/' + quiet);
  }
  // A separate canonical hub remains usable while B loads. Rejected B actions
  // must not change focus and readiness must follow the explicit owner.
  t.select(A); // The old hub's view is intentionally released on a machine switch.
  const sentA = t.wires(t.mail(A, 'mail-send')).filter((r: any) => r.m === 'mail.send');
  equal(sentA.length, 1, 'ready A accepts one action despite B recent state');
  equal(sentA[0].hub, A, 'same bot/conversation IDs cannot redirect owner');
  equal(sentA[0].p.conv, conv, 'opaque pipe-bearing conversation preserved');
  let out: any;
  if (end === 'history') out = t.recv(B, {t: 'changes', boot: false, items: []});
  else if (end === 'timeout') {
    t.act('thread-permissions', 'auto'); // ordinary recent action supplies the real expiry deadline
    t.advance(); out = JSON.parse(t.app.pulse());
  } else if (end === 'disconnect') out = JSON.parse(t.app.online(B, false));
  else out = JSON.parse(t.app.connection(B, 'new-epoch'));
  equal(t.wires(out).filter((r: any) => r.m === 'mail.send').length, 0, end + ' never sends a rejected tap');
  equal(t.wires(JSON.parse(t.app.flush(true))).filter((r: any) => r.m === 'mail.send').length, 0, 'later flush never sends rejected tap');
  if (end === 'history') {
    t.select(B);
    const body = t.screen().bot.mailroom.body;
    equal(body.messages[0].id, 'raw|stable', 'canonical typed cache survives actual handoff');
    equal(body.draft, 'retained local draft', 'presentation cannot overwrite canonical Mailroom draft');
    const sent = t.wires(t.mail(B, 'mail-send', '', false, {draft: 'captured exact 日本語'})).filter((r: any) => r.m === 'mail.send');
    equal(sent.length, 1, 'explicit post-ready tap emits exactly one ordinary mail.send');
    equal(sent[0].hub, B, 'post-ready send routes owning hub');
    equal(sent[0].p.text, 'captured exact 日本語', 'tap text used exactly');
    equal(t.screen().bot.mailroom.body.draft, 'retained local draft', 'captured send does not replace local edit');
  }
}
// Host language metadata is required on both render paths. A missing tag
// makes Swift's optional locale fall back to English during Recent.
for (const tag of ['en', 'ja']) {
  const t=setup();
  t.app.local('lang-preview','1');t.app.local('lang',tag);
  t.select(B);
  equal(t.screen().locale,tag,'canonical locale '+tag);
  t.startRecent(B);
  equal(t.screen().locale,tag,'original-shaped Recent locale '+tag);
  equal(t.wires(t.act('bot-tab','mail')).length,0,'localized loading tab stays blocked '+tag);
  const other=tag==='ja'?'en':'ja';
  t.app.local('lang',other);
  equal(t.screen().locale,other,'locale switch updates active presentation '+tag);
  t.app.local('lang',tag);
  equal(t.screen().locale,tag,'locale switch back updates active presentation '+tag);
  t.act('thread-permissions','auto');t.advance();t.app.pulse();
  equal(t.screen().locale,tag,'cached loading presentation keeps locale '+tag);
  t.app.local('lang',other);
  equal(t.screen().locale,other,'cached loading presentation changes locale '+tag);
  t.app.local('lang',tag);
  t.recv(B,{t:'changes',boot:false,items:[]});
  equal(t.screen().locale,tag,'canonical handoff keeps locale '+tag);
  t.select(B);
  equal(t.screen().bot.mailroom.body.messages[0].id,'raw|stable','localized handoff raw ID intact '+tag);
  equal(t.screen().bot.mailroom.body.messages[0].text,'Complete body 日本語','localized handoff complete text intact '+tag);
  equal(t.screen().bot.mailroom.body.draft,'retained local draft','localized handoff unsent draft intact '+tag);
}
const result = {pass: true, checks, scope: 'Emitted production bridge, actual canonical event/RPC caches and old-shaped presentation; no Swift/device/delivery/FPS claim'};
if (report) writeFileSync(report, JSON.stringify(result, null, 2) + '\n');
console.log('PASS production Mailroom bridge boundary ' + JSON.stringify(result));
