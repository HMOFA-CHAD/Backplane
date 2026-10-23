import record from '../../desktop/connection-record.cjs';
const { PREFIX, LIMIT, MAX_BYTES, sanitize, retained } = record;
const KEY = 'bp.connection.log.v1';
// Local metadata ring and an allowlisted desktop console record. No network IO.
export class ConnectionLog {
  constructor({ storage, bundle = '', now = Date.now, visibility = () => 'unknown', online = () => true,
    emit = x => console.info(PREFIX + JSON.stringify(x)) } = {}) {
    this.storage = storage; this.bundle = bundle; this.now = now; this.visibility = visibility; this.online = online; this.emit = emit;
    this.page = Array.from(globalThis.crypto?.getRandomValues(new Uint8Array(8)) || new Uint8Array(8), x => x.toString(16).padStart(2, '0')).join('');
    this.rows = []; this.next = 0;
    try { const text = storage?.getItem(KEY); if (text && text.length <= MAX_BYTES) this.rows = retained(JSON.parse(text), now()); } catch {}
  }
  record(event, detail = {}) {
    const r = sanitize({ ...detail, event, at: this.now(), page: this.page, bundle: this.bundle, visibility: this.visibility(), online: this.online() });
    if (!r) return;
    this.rows = retained(this.rows, this.now()).concat(r).slice(-LIMIT);
    try { this.storage?.setItem(KEY, JSON.stringify(this.rows)); } catch {}
    try { this.emit(r); } catch {}
  }
  connection() {
    const connection = ++this.next, began = this.now();
    let frameAt = began, heartbeatAt, lastFrameBytes = 0, cause, generation, epoch;
    const note = (event, extra = {}) => this.record(event, { connection, cause: cause || 'transport', generation, epoch,
      ageMs: Math.max(0, this.now() - began), frameAgeMs: Math.max(0, this.now() - frameAt),
      ...(heartbeatAt === undefined ? {} : { heartbeatAgeMs: Math.max(0, this.now() - heartbeatAt) }), lastFrameBytes, ...extra });
    return {
      note,
      frame: bytes => { frameAt = this.now(); lastFrameBytes = bytes; },
      heartbeat: () => { heartbeatAt = this.now(); },
      greeting: x => { generation = x.generation; epoch = x.epoch; note('greeting'); },
      initiate: why => { if (!cause) { cause = why; note('closing'); } },
      closed: e => note('closed', { closeCode: e?.code, wasClean: e?.wasClean, closeReason: e?.reason || '', reasonBytes: Math.min(123, (e?.reason || '').length) }),
    };
  }
}
