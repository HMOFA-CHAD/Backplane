// A bounded, read-only picture of the conversation actually rendered here.
// This is separate from the canonical CBOR frame cache and contains no Ui,
// replay cursor, actions, draft fields, pending sends or native guest handles.
export const VIEW_LIMIT = 512 * 1024;
const encoder = new TextEncoder(), decoder = new TextDecoder();
const TAGS = new Set('main header div span p pre code b strong i em ul ol li table thead tbody tr td th blockquote br hr a h1 h2 h3 h4 h5 h6'.split(' '));
export function cacheIdentity(cookie) {
  const values = cookie.split(';').map(x => x.trim()).filter(x => x.startsWith('bp_cache_v1=')).map(x => x.slice(12));
  return values.length === 1 && /^[0-9a-f]{64}$/.test(values[0]) ? values[0] : '';
}
export function scopeKey(c) {
  if (!c || !/^[0-9a-f]{64}$/.test(c.identity || '') || !c.origin || !c.cid || !c.bundle || !c.selected) return '';
  return JSON.stringify([1, c.origin, c.cid, c.identity, c.bundle, c.language, c.selected]);
}
function textPart(text, limit, tail) {
  const bytes = encoder.encode(text);
  if (bytes.length <= limit) return { text, bytes: bytes.length, clipped: false };
  let first = tail ? bytes.length - limit : 0, end = tail ? bytes.length : limit;
  if (tail) while (first < end && (bytes[first] & 192) === 128) first++;
  else while (end > 0 && (bytes[end] & 192) === 128) end--;
  return { text: decoder.decode(bytes.slice(first, end)), bytes: end - first, clipped: true };
}
function copyDOM(node, budget, tail, assistantStream = false) {
  if (budget.nodes-- <= 0 || budget.bytes <= 0) { budget.clipped = true; return null; }
  if (node.nodeType === 3) {
    const part = textPart(node.nodeValue || '', Math.min(8192, budget.bytes), tail);
    budget.bytes -= part.bytes; budget.clipped ||= part.clipped;
    return { type: 'text', text: part.text };
  }
  const tag = node.tagName?.toLowerCase();
  if (node.nodeType !== 1 || node.hidden || !TAGS.has(tag)) return null;
  const cls = node.getAttribute('class') || '';
  const classes = cls.split(/\s+/);
  if (classes.includes('phase')) return null;
  if (/(^|\s)(sending|queued|pending|composer|asks)(\s|$)/.test(cls)) return null;
  if (/(^|\s)live(\s|$)/.test(cls) && !assistantStream) return null;
  // A saved stream is text last seen here, never active after reload.
  // Neither a normal live row nor a bounded synthetic id is a committed id.
  const dot = classes.some(c => ['dot', 'indicator-dot', 'state-dot'].includes(c));
  const savedClass = classes.filter(c => c && c !== 'live').map(c => dot && c === 'active' ? 'inactive' : c).join(' ');
  const attrs = savedClass ? [{ name: 'class', value: savedClass.slice(0, 256) }] : [];
  if (dot) return { type: 'element', tag, key: '', attrs, kids: [] };
  // No href/src/value/data-*/event attributes can survive this transport.
  const kids = [];
  const children = tail ? Array.from(node.childNodes).reverse() : node.childNodes;
  for (const child of children) {
    if (budget.nodes <= 0 || budget.bytes <= 0) { budget.clipped = true; break; }
    const value = copyDOM(child, budget, tail); if (value) kids.push(value);
  }
  if (tail) kids.reverse();
  return { type: 'element', tag, key: '', attrs, kids };
}
export function captureFocused({ main, timeline, title, scope, epoch, shellAttrs = [], now = Date.now() }) {
  const key = scopeKey(scope);
  if (!key || !main || !timeline || !title || !epoch) return null;
  const bounds = timeline.getBoundingClientRect();
  const stream = e => e.classList.contains('msg') && e.classList.contains('assistant')
    && (e.classList.contains('live') || e.getAttribute('data-id') === '@live:' + scope.selected);
  const all = Array.from(timeline.children).filter(e => e.classList.contains('msg')
    && !['sending','queued','pending','composer','asks'].some(c => e.classList.contains(c))
    && (!e.getAttribute('data-id')?.startsWith('@live:') || stream(e))
    && (stream(e) || e.hasAttribute('data-id') && !e.classList.contains('live')));
  const visible = all.filter(e => { const r = e.getBoundingClientRect(); return r.bottom >= bounds.top - timeline.clientHeight && r.top <= bounds.bottom + timeline.clientHeight; });
  const rows = (visible.length ? visible : all).slice(-40);
  if (!rows.length) return null;
  const atEnd = timeline.scrollHeight - timeline.scrollTop - timeline.clientHeight <= 16;
  const budget = { bytes: 256 * 1024, nodes: 1800, clipped: all.length > rows.length }, kids = [];
  const heading = copyDOM(title, budget, false);
  // Give the most recently visible assistant/committed text priority under
  // the cap, including a conversation whose only response is still streaming.
  for (const row of [...rows].reverse()) { const n = copyDOM(row, budget, atEnd, stream(row)); if (n) kids.unshift(n); }
  const snapshot = { format: 1, key, ...scope, epoch, savedAt: now, atEnd, partial: rows.some(stream), clipped: budget.clipped, rows: kids.length,
    shellAttrs: shellAttrs.filter(a => a.name === 'class' || a.name === 'style' && /^--text-scale:\s*\d+;?$/.test(a.value)),
    main: { type: 'element', tag: 'main', key: 'cached-main', attrs: [{ name: 'class', value: 'thread-view' }, { name: 'aria-busy', value: 'true' }], kids: [
      { type: 'element', tag: 'header', key: '', attrs: [{ name: 'class', value: 'thread-head' }], kids: heading ? [heading] : [] },
      { type: 'element', tag: 'div', key: 'cached-timeline', attrs: [{ name: 'class', value: 'timeline' }, { name: 'id', value: 'timeline' }], kids }] } };
  return encoder.encode(JSON.stringify(snapshot)).length <= VIEW_LIMIT ? snapshot : null;
}
export function validFocused(record, scope) {
  try {
    if (!record || record.format !== 1 || record.key !== scopeKey(scope) || record.key !== scopeKey(record)
      || !record.epoch || !Number.isFinite(record.savedAt) || encoder.encode(JSON.stringify(record)).length > VIEW_LIMIT) return false;
    let left = 2000;
    const check = (node, depth) => {
      if (!node || depth > 48 || --left < 0) return false;
      if (node.type === 'text') return typeof node.text === 'string';
      if (node.type !== 'element' || !TAGS.has(node.tag) || !Array.isArray(node.kids) || !Array.isArray(node.attrs)) return false;
      if (!node.attrs.every(a => typeof a.value === 'string' && (a.name === 'class' || a.name === 'aria-busy' && a.value === 'true' || a.name === 'id' && a.value === 'timeline'))) return false;
      if (new Set(node.attrs.map(a => a.name)).size !== node.attrs.length) return false;
      const classes = (node.attrs.find(a => a.name === 'class')?.value || '').split(/\s+/);
      if (classes.includes('phase') || classes.includes('active') && classes.some(c => ['dot', 'indicator-dot', 'state-dot'].includes(c))) return false;
      return node.kids.every(n => check(n, depth + 1));
    };
    return check(record.main, 0) && record.shellAttrs.every(a => typeof a.value === 'string' && (a.name === 'class' || a.name === 'style' && /^--text-scale:\s*\d+;?$/.test(a.value)));
  } catch { return false; }
}
export function mergeFocused(shell, record) {
  if (shell.type !== 'element') return shell;
  if (shell.tag === 'main') return record.main;
  return { ...shell, attrs: shell.key === 'app' && record.shellAttrs.length ? record.shellAttrs : shell.attrs, kids: shell.kids.map(n => mergeFocused(n, record)) };
}
export class FocusedCache {
  constructor({ indexedDB, report = () => {} }) { this.indexedDB = indexedDB; this.report = report; }
  open() {
    if (this.opened) return this.opened;
    return this.opened = new Promise(resolve => {
      let settled = false;
      const finish = db => { if (settled) { db?.close(); return; } settled = true; clearTimeout(timer); resolve(db); };
      const timer = setTimeout(() => { this.report('unavailable', 'open deadline'); finish(null); }, 1500);
      try {
        const r = this.indexedDB.open('backplane-focused-v1', 1);
        r.onupgradeneeded = () => { const s = r.result.createObjectStore('views', { keyPath: 'key' }); s.createIndex('savedAt', 'savedAt'); };
        r.onsuccess = () => finish(r.result);
        r.onerror = () => { this.report('unavailable', 'open error'); finish(null); };
        r.onblocked = () => { this.report('unavailable', 'open blocked'); finish(null); };
      } catch { finish(null); }
    });
  }
  async get(scope) {
    const key = scopeKey(scope);
    if (!key) { this.report('miss', 'identity or selection absent'); return null; }
    const db = await this.open(); if (!db) return null;
    return new Promise(resolve => {
      let settled = false;
      const finish = record => { if (settled) return; settled = true; clearTimeout(timer); resolve(record); };
      const timer = setTimeout(() => { this.report('miss', 'read deadline'); finish(null); }, 1500);
      try {
        const r = db.transaction('views').objectStore('views').get(key);
        r.onsuccess = () => { if (settled) return; const record = validFocused(r.result, scope) ? r.result : null; this.report(record ? 'hit' : 'miss', record ? 'persisted selected view' : 'scope or data mismatch'); finish(record); };
        r.onerror = () => finish(null);
      } catch { finish(null); }
    });
  }
  async put(record) {
    if (!validFocused(record, record)) { this.report('skipped', 'invalid or oversized'); return false; }
    const db = await this.open(); if (!db) return false;
    return new Promise(resolve => {
      let settled = false;
      const finish = ok => { if (settled) return; settled = true; clearTimeout(timer); this.report(ok ? 'committed' : 'unavailable', ok ? 'selected view durable' : 'write failed'); resolve(ok); };
      let tx;
      const timer = setTimeout(() => { try { tx?.abort(); } catch {} finish(false); }, 1500);
      try {
        tx = db.transaction('views', 'readwrite');
        const store = tx.objectStore('views'); store.put(record);
        const count = store.count();
        count.onsuccess = () => {
          let excess = count.result - 40;
          if (excess <= 0) return;
          const cursor = store.index('savedAt').openKeyCursor();
          cursor.onsuccess = () => { const c = cursor.result; if (!c || excess-- <= 0) return; store.delete(c.primaryKey); c.continue(); };
        };
        tx.oncomplete = () => finish(true);
        tx.onerror = tx.onabort = () => finish(false);
      } catch { finish(false); }
    });
  }
  async remove(scope) {
    const key = scopeKey(scope), db = key && await this.open();
    if (!db) return false;
    return new Promise(resolve => {
      let tx, finished = false;
      const done = ok => { if (finished) return; finished = true; clearTimeout(timer); resolve(ok); };
      const timer = setTimeout(() => { try { tx?.abort(); } catch {} done(false); }, 1500);
      try {
        tx = db.transaction('views', 'readwrite');tx.objectStore('views').delete(key);
        tx.oncomplete = () => done(true);tx.onerror = tx.onabort = () => done(false);
      } catch { done(false); }
    });
  }
}

// Async IO is fenced by the actual current selection and credential partition.
// No cached object ever becomes a session, action source or sequence cursor.
export class FocusedView {
  constructor(api) { this.api = api; this.revision = 0; this.record = null; }
  async restore() {
    const revision = ++this.revision, scope = this.api.scope(), key = scopeKey(scope);
    const kept = validFocused(this.record, scope);
    if (!kept) { this.record = null;this.api.hide(); }
    if (!key) return false;
    const record = await this.api.cache.get(scope);
    if (revision !== this.revision) return false;
    if (key !== scopeKey(this.api.scope())) { this.invalidate();return false; }
    if (!validFocused(record, scope)) return kept;
    this.record = record;this.api.view(record);return true;
  }
  invalidate() { this.revision++;this.record = null;this.api.hide(); }
  remote(epoch) {
    const record = this.record;
    this.invalidate();
    if (record && record.epoch !== epoch) void this.api.cache.remove(record);
  }
  async save(record) {
    if (!record || record.key !== scopeKey(this.api.scope())) return false;
    return this.api.cache.put(record);
  }
}
