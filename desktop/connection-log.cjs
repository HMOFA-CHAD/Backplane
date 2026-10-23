'use strict';
const fs = require('node:fs'), path = require('node:path');
const { PREFIX, LIMIT, MAX_BYTES, sanitize, retained } = require('./connection-record.cjs');
function createConnectionLog(home, { now = Date.now } = {}) {
  const file = path.join(home, 'connection-log.json');
  let rows = [], bucket = 0, writes = 0;
  try { if (fs.statSync(file).size <= MAX_BYTES) rows = retained(JSON.parse(fs.readFileSync(file)), now()); } catch {}
  function record(input) {
    const value = sanitize({ ...input, at: now(), process: process.pid });
    if (!value) return false;
    // A compromised/misbehaving renderer cannot create an unbounded write stream.
    const second = Math.floor(now() / 1000);
    if (second !== bucket) { bucket = second; writes = 0; }
    if (++writes > 12) return false;
    rows = retained(rows, now()).concat(value).slice(-LIMIT);
    let text = JSON.stringify(rows);
    while (Buffer.byteLength(text) > MAX_BYTES && rows.length > 1) { rows.shift(); text = JSON.stringify(rows); }
    try { fs.mkdirSync(home, { recursive: true }); fs.writeFileSync(file + '.tmp', text + '\n', { mode: 0o600 }); fs.renameSync(file + '.tmp', file); } catch { return false; }
    return true;
  }
  function capture(message) {
    if (typeof message !== 'string' || message.length > 2048 || !message.startsWith(PREFIX)) return false;
    try { return record(JSON.parse(message.slice(PREFIX.length))); } catch { return false; }
  }
  return { record, capture, file };
}
module.exports = { createConnectionLog };
