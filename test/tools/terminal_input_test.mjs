import assert from 'node:assert/strict';
import { ThinHost } from '../../src/web/thin-host.js';
import { ThinViews, VIEW_LIMITS } from '../../src/web/thin.js';
import { terminalInputRequest, terminalInputReply } from '../../src/web/terminal-input.js';

const clone = value => structuredClone(value);
const picture = { type: 'text', text: 'fixture conversation' };
const initial = { sel: 'a', rid: 10, drafts: { a: 'unsent', '@terminal.owner': 'a' }, outbox: {}, open: { term: true }, info: {}, adding: false, panel: false };
const window = { ids: [], older: '', hasMore: false, anchor: { id: '', offset: 0 }, partial: [] };
function setup() {
  const sent = [], commands = [], views = [], sessions = [], states = [], decoded = [];
  const h = new ThinHost({ hub: 'h', now: () => 0, cid: 'fixture', session: () => clone(initial),
    target: s => ({ kind: 'thread', id: s.sel }), counter() {}, send: r => sent.push(r),
    prepare: session => session, choice: (session, action, value) => ({ ...session, sel: action === 'select' ? value : session.sel }),
    local() {}, sessionChanged: (s, d) => sessions.push({ s: clone(s), d }),
    decode: shown => { decoded.push(shown);return shown; }, command: c => commands.push(c),
    view: v => views.push(v), state: s => states.push(s), anchor: () => ({ id: '', offset: 0 }),
    ack: s => s, blocked() {}, warning() {},
  }, ThinViews);
  const envelope = (request, extra = {}) => ({ t: 'reply', id: request.id, ok: true, result: {
    version: 1, hub: 'h', generation: '3', epoch: 'e', requestRevision: request.p.requestRevision,
    target: clone(request.p.target), viewId: request.p.viewId || 'v1', viewRevision: '1', renderer: 'web', remoteReady: true,
    session: clone(h.session), shown: clone(picture), window: clone(window), cmds: [], ...extra,
  } });
  const inputAck = (request, bytes = [97]) => {
    const r = envelope(request, { terminalInput: true, terminalOwner: request.p.terminalOwner, viewRevision: '2',
      session: { ...clone(h.session), rid: h.session.rid + 1 },
      cmds: [{ type: 'send', text: JSON.stringify({ id: h.session.rid + 1, m: 'term.input', p: { thread: request.p.terminalOwner, b: bytes } }) }],
    });
    delete r.result.shown;delete r.result.window;return r;
  };
  h.greeting({ t: 'view', version: 1, renderer: 'web', generation: '3', epoch: 'e', limits: VIEW_LIMITS });
  h.receive(envelope(sent.at(-1)));
  return { h, sent, commands, views, sessions, states, decoded, envelope, inputAck };
}
let checks = 0;
function check(name, run) { run();checks++;console.log('ok ' + name); }

check('opt-in is only visible floating input, with captured retained owner', () => {
  assert.deepEqual(terminalInputRequest('term-key', initial), { terminalInput: true, terminalOwner: 'a' });
  for (const action of ['term-toggle', 'ws-key', 'ws-term-hide', 'ws-term-resize', 'emb-key', 'send']) assert.deepEqual(terminalInputRequest(action, initial), {});
  assert.deepEqual(terminalInputRequest('term-key', { ...initial, open: {} }), {});
  assert.deepEqual(terminalInputRequest('term-paste', { ...initial, drafts: {} }), {});
});
check('input ACK settles once, skips decode/view, keeps picture and display revision', () => {
  const f = setup();let settled;
  f.h.request('term-key', 'a\t0', ok => { settled = ok; });const request = f.sent.at(-1), r = f.inputAck(request);
  assert.equal(request.p.terminalInput, true);assert.equal(request.p.terminalOwner, 'a');
  f.h.receive(r);assert.equal(settled, true);assert.equal(f.commands.length, 1);assert.equal(f.views.length, 1);assert.equal(f.decoded.length, 1);
  assert.deepEqual(f.h.client.links.get('h').shown, picture);assert.equal(f.h.client.links.get('h').viewRevision, '1');
  assert.equal(f.sessions.at(-1).d.inputOnly, true);assert.equal(f.h.session.drafts.a, 'unsent');
  f.h.receive(r);assert.equal(f.commands.length, 1);
});
check('output invalidation is deferred through input, then fetched with original picture revision', () => {
  const f = setup();f.h.request('term-key', 'a\t0');const request = f.sent.at(-1), before = f.sent.length;
  f.h.receive({ t: 'view.changed', version: 1, generation: '3', epoch: 'e', viewId: 'v1', target: { kind: 'thread', id: 'a' }, viewRevision: '2' });
  assert.equal(f.sent.length, before);f.h.receive(f.inputAck(request));
  assert.equal(f.sent.at(-1).m, 'view.update');assert.equal(f.sent.at(-1).p.viewRevision, '1');assert.equal(f.sent.at(-1).p.terminalInput, undefined);
});
check('existing FIFO keeps queued paste after key and its exact owner', () => {
  const f = setup();f.h.request('term-key', 'a\t0');const first = f.sent.at(-1);f.h.request('term-paste', 'fixture');
  assert.equal(f.sent.at(-1).id, first.id);f.h.receive(f.inputAck(first));const second = f.sent.at(-1);
  assert.equal(second.p.action, 'term-paste');assert.equal(second.p.terminalOwner, 'a');assert.notEqual(second.id, first.id);
});
check('old travelling action retains its original command, without changing new selection/readiness', () => {
  const f = setup();f.h.request('term-key', 'a\t0');const request = f.sent.at(-1), old = f.inputAck(request);
  f.h.request('select', 'b');f.h.receive(old);
  assert.equal(f.commands.length, 1);assert.equal(JSON.parse(f.commands[0].text).p.thread, 'a');
  assert.equal(f.h.session.sel, 'b');assert.equal(f.h.ready, false);assert.equal(f.views.length, 1);
});
check('old service full reply remains supported for an opted-in key', () => {
  const f = setup();f.h.request('term-key', 'a\t0');f.h.receive(f.envelope(f.sent.at(-1)));
  assert.equal(f.h.ready, true);assert.equal(f.views.length, 2);assert.equal(f.decoded.length, 2);
});
check('unsolicited/nonterminal/read ACKs cannot run commands', () => {
  for (const action of ['send', 'term-toggle', 'ws-term-hide']) {
    const f = setup();f.h.request(action, '');const request = f.sent.at(-1), r = f.inputAck(request);
    r.result.terminalOwner = 'a';f.h.receive(r);assert.equal(f.commands.length, 0);assert.equal(f.h.ready, false);
  }
  const f = setup(), request = f.sent[0], r = f.inputAck(request);
  r.result.terminalOwner = 'a';assert.equal(terminalInputReply(r.result, request.p), false);
});
check('wrong owner, arbitrary effect, malformed bytes and picture injection reject atomically', () => {
  for (const mutate of [
    r => { r.result.terminalOwner = 'b'; },
    r => { r.result.session.drafts['@terminal.owner'] = 'b'; },
    r => { r.result.cmds[0].text = JSON.stringify({ id: 30, m: 'term.input', p: { thread: 'b', b: [97] } }); },
    r => { r.result.cmds[0].text = JSON.stringify({ id: 30, m: 'turn.start', p: {} }); },
    r => { r.result.cmds.push({ type: 'copy', text: 'unexpected' }); },
    r => { r.result.cmds[0].text = JSON.stringify({ id: 30, m: 'term.input', p: { thread: 'a', b: [256] } }); },
    r => { r.result.shown = picture; }, r => { r.result.window = window; }, r => { r.result.nextTarget = { kind: 'thread', id: 'b' }; },
    r => { r.result.epoch = 'stale'; }, r => { r.result.requestRevision++; },
  ]) {
    const f = setup();f.h.request('term-key', 'a\t0');const r = f.inputAck(f.sent.at(-1));mutate(r);f.h.receive(r);
    assert.equal(f.commands.length, 0);assert.equal(f.views.length, 1);assert.equal(f.h.ready, false);
  }
});
console.log(JSON.stringify({ pass: true, checks, scope: 'Terminal input ACK source-level transport/host guards. No emitted service, PTY timing, live UI or output responsiveness claim.' }));
