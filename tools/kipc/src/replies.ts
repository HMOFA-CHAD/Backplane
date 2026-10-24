// A worker owns one IPC connection. Ending that connection must answer its
// outstanding requests as errors, rather than leave the hub's MCP waits open.
// A disconnected request may have reached KiCad: an error is not a rollback.
export type Reply = { bytes?: Uint8Array; error?: string };

export class Replies {
  private pending = new Map<string, (reply: Reply) => void>();
  private ended = "";

  constructor(private worker: Worker, private detached: () => void) {
    worker.onmessage = (ev: MessageEvent) => {
      const reply = ev.data as Reply & { op?: string; id?: string };
      if (reply.op !== "reply" || reply.id === undefined) return;
      const resolve = this.pending.get(reply.id);
      this.pending.delete(reply.id);
      resolve?.(reply);
    };
    worker.onerror = () => this.end("KiCad IPC worker failed; request outcome unknown");
    worker.addEventListener("close", () => this.end("KiCad IPC worker exited; request outcome unknown"));
  }

  request(id: string, message: object): Promise<Reply> {
    if (this.ended) return Promise.resolve({ error: this.ended });
    if (this.pending.has(id)) return Promise.resolve({ error: "duplicate IPC request id" });
    return new Promise((resolve) => {
      this.pending.set(id, resolve);
      try {
        this.worker.postMessage(message);
      } catch (error) {
        // An enqueue error belongs to this request; other requests may be live.
        this.pending.delete(id);
        resolve({ error: `could not enqueue KiCad IPC request: ${String(error)}` });
      }
    });
  }

  private end(error: string) {
    if (this.ended) return;
    this.ended = error;
    const pending = this.pending;
    this.pending = new Map();
    this.detached();
    for (const resolve of pending.values()) resolve({ error });
  }

  close() {
    // Only used by the existing per-socket close operation. Never signal KiCad
    // or another connection, and never infer completion from a client timeout.
    this.end("KiCad IPC connection closed; request outcome unknown");
    this.worker.terminate();
  }
}
