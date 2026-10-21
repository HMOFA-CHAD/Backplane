import { utf8Bytes } from './thin.js';

// A local reply draft is text only. This adapter never issues an action and
// never adopts the Ui returned by the legacy snapshot decoder.
export function mailDraftContext(value, epoch) {
  if (!value || typeof value !== 'object' || Array.isArray(value)
    || Object.keys(value).sort().join(',') !== 'conv,kind,origin,owner,recipient'
    || value.kind !== 'mail-draft' || value.origin !== epoch) return null;
  for (const key of ['owner', 'origin', 'conv', 'recipient']) {
    if (typeof value[key] !== 'string' || utf8Bytes(value[key]) > 1024 || key !== 'recipient' && !value[key]) return null;
  }
  return value;
}
export function mailReplyField(shown) {
  const pending = [shown];let remaining = 20000, found;
  while (pending.length) {
    if (--remaining < 0) return undefined;
    const node = pending.pop();
    if (node?.type !== 'element') continue;
    const attrs = node.attrs || [];
    if (node.tag === 'textarea' && attrs.some(a => a.name === 'data-bfield' && a.value === 'mrreply')) {
      if (found !== undefined) return undefined;
      found = attrs.find(a => a.name === 'value')?.value;
      if (typeof found !== 'string') return undefined;
    }
    for (const child of node.kids || []) pending.push(child);
  }
  return found;
}
export class ThinMailDraft {
  constructor(api) { this.api = api;this.active = null;this.restored = false;this.text = ''; }
  credential() { const tag = this.api.identity();return typeof tag === 'string' && /^[0-9a-f]{64}$/.test(tag) ? tag : ''; }
  matches(context, epoch) {
    const current = mailDraftContext(context, epoch);
    return !!current && this.active?.tag === this.credential() && this.active?.identity === JSON.stringify([current.origin, current.owner, current.conv]);
  }
  scope(recipient = false) { return this.active ? JSON.stringify([this.active.tag, this.active.identity, ...(recipient ? [this.active.recipient] : [])]) : ''; }
  clear() {
    this.checkpoint();this.active = null;this.restored = false;this.text = '';
    this.api.context(null);this.api.field('');
  }
  bind(context, epoch, acceptedText) {
    const current = mailDraftContext(context, epoch);
    if (!current || typeof acceptedText !== 'string') { this.clear();return; }
    const tag = this.credential(), identity = JSON.stringify([current.origin, current.owner, current.conv]);
    const same = this.active?.identity === identity && this.active?.tag === tag;
    if (!same) this.checkpoint();
    this.api.context(current);
    const localKey = this.api.key();
    // The legacy MA key is insufficient across credential rotation. A missing
    // public credential tag disables persistence, including old-key reads.
    const key = tag && localKey ? 'backplane-mail-v2:' + JSON.stringify([tag, localKey]) : '';
    let text = acceptedText, restored = false;
    if (same && this.restored && acceptedText === '') { text = this.text;restored = true; }
    else if (!same && key && acceptedText === '') {
      try {
        const saved = this.api.read(key);
        if (typeof saved === 'string' && utf8Bytes(saved) <= 262144) {
          const local = this.api.restoreText(saved);
          if (typeof local === 'string' && local) { text = local;restored = true; }
        }
      } catch {} // Corrupt/unavailable local storage cannot block a live view.
    }
    this.active = { tag, identity, key, recipient: current.recipient };this.restored = restored;this.text = text;
    this.api.field(text);this.checkpoint();
  }
  edit(text) {
    if (!this.active || typeof text !== 'string') return;
    this.restored = false;this.text = text;this.api.field(text);this.checkpoint();
  }
  fieldValue(name, fallback) { return name === 'mrreply' && this.active && this.restored ? this.text : fallback; }
  needsSubmit() { return !!this.active && this.restored; }
  checkpoint() {
    if (!this.active?.key || this.active.tag !== this.credential()) return;
    try {
      // A pure session handoff may have replaced scratch since the last
      // render. Persist the field actually accepted/displayed by this owner.
      this.api.field(this.text);
      const snapshot = JSON.parse(this.api.snapshot());
      // Retain the existing Bend snapshot's draft policy, with no receipt,
      // state, pending id or outbox data crossing the local persistence seam.
      if (typeof snapshot.draft !== 'string') return;
      const text = JSON.stringify({ draft: snapshot.draft });
      if (utf8Bytes(text) <= 262144) this.api.write(this.active.key, text);
    } catch {} // Never sends, retries or discards the displayed draft.
  }
}
