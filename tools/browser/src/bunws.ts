// Only the CEF CDP connection uses this adapter. Chrome keeps Playwright's ws.
import { EventEmitter } from "node:events";
export class BunWs extends EventEmitter {
  static CONNECTING = 0; static OPEN = 1; static CLOSING = 2; static CLOSED = 3;
  static connections = new Map<string, BunWs>();
  pages = new Map<string, string>();
  others = new Map<string, string>();
  private calls = new Map<number, { resolve: (v: any) => void; reject: (e: Error) => void; timer: ReturnType<typeof setTimeout> }>();
  private nextCall = 1_000_000_000;
  w: WebSocket;
  constructor(url: string, _protocols: string[], opts: any = {}) {
    super();
    BunWs.connections.set(url, this);
    this.w = new WebSocket(url, { headers: opts.headers } as any);
    this.w.onopen = () => this.emit("open");
    this.w.onmessage = (e) => {
      const data = typeof e.data === "string" ? e.data : Buffer.from(e.data as ArrayBuffer).toString();
      const msg = JSON.parse(data);
      const call = this.calls.get(msg.id);
      if (call) {
        this.calls.delete(msg.id); clearTimeout(call.timer);
        if (msg.error) call.reject(new Error(msg.error.message)); else call.resolve(msg.result);
        return;
      }
      if (!msg.sessionId && msg.method === "Target.attachedToTarget" && msg.params.targetInfo.type === "page")
        this.pages.set(msg.params.targetInfo.targetId, msg.params.sessionId);
      if (!msg.sessionId && msg.method === "Target.attachedToTarget" && msg.params.targetInfo.type === "other")
        this.others.set(msg.params.targetInfo.targetId, msg.params.sessionId);
      if (!msg.sessionId && msg.method === "Target.detachedFromTarget") {
        if (this.pages.get(msg.params.targetId) === msg.params.sessionId) this.pages.delete(msg.params.targetId);
        if (this.others.get(msg.params.targetId) === msg.params.sessionId) this.others.delete(msg.params.targetId);
      }
      this.emit("message", { data });
    };
    this.w.onclose = (e) => {
      if (BunWs.connections.get(url) === this) BunWs.connections.delete(url);
      for (const c of this.calls.values()) { clearTimeout(c.timer); c.reject(new Error("CEF CDP disconnected")); }
      this.calls.clear(); this.pages.clear(); this.others.clear();
      this.emit("close", { code: e.code, reason: e.reason, wasClean: e.wasClean });
    };
    this.w.onerror = () => this.emit("error", { type: "error", message: "websocket error" });
  }
  get readyState() { return this.w.readyState; }
  addEventListener(ev: string, f: (...a: any[]) => void) { this.on(ev, f); }
  removeEventListener(ev: string, f: (...a: any[]) => void) { this.off(ev, f); }
  send(s: string) { this.w.send(s); }
  // Host-created CEF targets briefly have type "other", which Playwright's
  // auto-attach ignores. Attach the final page on Playwright's root session;
  // a separate Browser CDPSession would not deliver its Page to Playwright.
  request(method: string, params: Record<string, any>): Promise<any> {
    const id = this.nextCall++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.calls.delete(id); reject(new Error(`CEF CDP ${method} timed out`)); }, 15000);
      this.calls.set(id, { resolve, reject, timer });
      this.w.send(JSON.stringify({ id, method, params }));
    });
  }
  close(code?: number, reason?: string) { this.w.close(code, reason); }
}
// Source transform rather than assigning utilsBundle.ws (a read-only getter).
export function patchCefWs(source: string): string {
  const from = "this._ws = new ws(url3, [], {";
  if (!source.includes(from)) throw new Error("Playwright CEF ws patch no longer matches coreBundle.js");
  return source.replace(from, "this._ws = new (globalThis.__bpCefWs ? globalThis.__bpWs : ws)(url3, [], {");
}
(globalThis as any).__bpWs = BunWs;
