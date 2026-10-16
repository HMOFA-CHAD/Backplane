// Only the CEF CDP connection uses this adapter. Chrome keeps Playwright's ws.
import { EventEmitter } from "node:events";
export class BunWs extends EventEmitter {
  static CONNECTING = 0; static OPEN = 1; static CLOSING = 2; static CLOSED = 3;
  w: WebSocket;
  constructor(url: string, _protocols: string[], opts: any = {}) {
    super();
    this.w = new WebSocket(url, { headers: opts.headers } as any);
    this.w.onopen = () => this.emit("open");
    this.w.onmessage = (e) => this.emit("message", { data: typeof e.data === "string" ? e.data : Buffer.from(e.data as ArrayBuffer).toString() });
    this.w.onclose = (e) => this.emit("close", { code: e.code, reason: e.reason, wasClean: e.wasClean });
    this.w.onerror = () => this.emit("error", { type: "error", message: "websocket error" });
  }
  get readyState() { return this.w.readyState; }
  addEventListener(ev: string, f: (...a: any[]) => void) { this.on(ev, f); }
  removeEventListener(ev: string, f: (...a: any[]) => void) { this.off(ev, f); }
  send(s: string) { this.w.send(s); }
  close(code?: number, reason?: string) { this.w.close(code, reason); }
}
// Source transform rather than assigning utilsBundle.ws (a read-only getter).
export function patchCefWs(source: string): string {
  const from = "this._ws = new ws(url3, [], {";
  if (!source.includes(from)) throw new Error("Playwright CEF ws patch no longer matches coreBundle.js");
  return source.replace(from, "this._ws = new (globalThis.__bpCefWs ? globalThis.__bpWs : ws)(url3, [], {");
}
(globalThis as any).__bpWs = BunWs;
