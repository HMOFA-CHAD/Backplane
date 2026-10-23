const { test } = require('node:test'), assert = require('node:assert/strict');
const { installShortcuts } = require('../window.cjs');
const event = (key, fields = {}) => ({ key, code: '', ctrlKey: false, metaKey: false, altKey: false, shiftKey: false, target: { closest: () => null }, ...fields });

test('restored navigation chords respect editors, IME, PTYs and platform modifiers', async () => {
  const { workspaceShortcut: key } = await import('../../src/web/workspace-keys.js');
  assert.deepEqual(key(event('2', { altKey: true }), 'Linux'), ['ws-key', 'alt+2']);
  assert.deepEqual(key(event('2', { ctrlKey: true }), 'Linux'), ['ws-key', 'ctrl+2']);
  assert.deepEqual(key(event('}', { ctrlKey: true, shiftKey: true, code: 'BracketRight' }), 'Linux'), ['ws-key', 'next']);
  assert.deepEqual(key(event('U', { ctrlKey: true, shiftKey: true }), 'Linux'), ['ws-key', 'uber']);
  const editor = { closest: () => ({}) };
  for (const input of [event('2', { altKey: true, target: editor }), event('2', { ctrlKey: true, target: editor }),
    event('}', { ctrlKey: true, shiftKey: true, target: editor }), event('U', { ctrlKey: true, shiftKey: true, target: editor }),
    event('P', { ctrlKey: true, shiftKey: true, isComposing: true }), event('2', { altKey: true, getModifierState: () => true })]) assert.equal(key(input, 'Linux'), null);
  assert.deepEqual(key(event('P', { ctrlKey: true, shiftKey: true, target: editor }), 'Linux'), ['ws-palette-open', '']);
  assert.deepEqual(key(event('P', { metaKey: true, shiftKey: true }), 'MacIntel'), ['ws-palette-open', '']);
  assert.deepEqual(key(event('~', { metaKey: true, shiftKey: true, code: 'Backquote', target: editor }), 'Linux'), ['ws-key', 'term']);
  assert.equal(key(event('~', { metaKey: true, shiftKey: true, code: 'Backquote' }), 'MacIntel'), null);
});

test('Electron passes shell control keys to a focused PTY and keeps terminal clipboard chords', () => {
  let handler, prevented = 0; const calls = [];
  const contents = { on: (_name, value) => { handler = value; }, copy: () => calls.push('copy'), paste: () => calls.push('paste') };
  installShortcuts({ webContents: contents }, { app: {}, webContents: { getFocusedWebContents: () => contents } }, undefined, 'linux', () => true);
  const press = (key, shift = false) => handler({ preventDefault: () => prevented++ }, { type: 'keyDown', key, control: true, shift });
  for (const key of ['c', 'a', 'z', 'r', 'd', 'p']) press(key);
  assert.equal(prevented, 0);assert.deepEqual(calls, []);
  press('c', true);press('v', true);assert.equal(prevented, 2);assert.deepEqual(calls, ['copy', 'paste']);
});
