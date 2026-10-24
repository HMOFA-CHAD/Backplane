import { expect, test } from "bun:test";
import { Replies, type Reply } from "../src/replies.ts";

// No native connection, helper process, board, or installed runtime is used.
class WorkerStub {
  onmessage?: (ev: MessageEvent) => void;
  onerror?: () => void;
  closed?: () => void;
  messages: object[] = [];
  terminated = false;
  throws = false;
  addEventListener(event: string, callback: () => void) {
    if (event === "close") this.closed = callback;
  }
  postMessage(message: object) {
    if (this.throws) throw new Error("enqueue failed");
    this.messages.push(message);
  }
  terminate() { this.terminated = true; }
  reply(id: string, result: Reply) {
    this.onmessage?.({ data: { op: "reply", id, ...result } } as MessageEvent);
  }
}
const make = () => {
  const worker = new WorkerStub();
  let detached = 0;
  const replies = new Replies(worker as unknown as Worker, () => detached++);
  return { worker, replies, detached: () => detached };
};
const bounded = (reply: Promise<Reply>) => Promise.race([
  reply,
  new Promise<never>((_, reject) => setTimeout(() => reject(new Error("orphaned reply")), 100)),
]);

test("closing an old connection answers its two waits and preserves a different live connection", async () => {
  const old = make(), live = make();
  const a = old.replies.request("1", {}), b = old.replies.request("2", {});
  let liveDone = false;
  const c = live.replies.request("3", {}).then((r) => { liveDone = true; return r; });
  old.replies.close();
  expect((await bounded(a)).error).toMatch(/closed.*outcome unknown/);
  expect((await bounded(b)).error).toMatch(/closed.*outcome unknown/);
  expect(liveDone).toBe(false);
  expect(live.worker.terminated).toBe(false);
  live.worker.reply("3", { bytes: new Uint8Array([7]) });
  expect((await bounded(c)).bytes).toEqual(new Uint8Array([7]));
  expect(old.detached()).toBe(1);
  expect(live.detached()).toBe(0);
});

test.each(["error", "exit"])("worker %s answers pending calls once without successful output", async (kind) => {
  const s = make();
  const request = s.replies.request("4", {});
  if (kind === "error") s.worker.onerror?.(); else s.worker.closed?.();
  const result = await bounded(request);
  expect(result.error).toMatch(/worker.*outcome unknown/);
  expect(result.bytes).toBeUndefined();
  s.worker.closed?.();
  s.worker.onerror?.();
  s.worker.reply("4", { bytes: new Uint8Array([1]) });
  expect(s.detached()).toBe(1);
  expect(await s.replies.request("5", {})).toEqual(result);
});

test("late response/error from a retired worker cannot complete a replacement's same-id request", async () => {
  const old = make(), replacement = make();
  const previous = old.replies.request("same", {});
  old.replies.close();
  expect((await bounded(previous)).error).toBeDefined();
  let complete = false;
  const current = replacement.replies.request("same", {}).then((r) => { complete = true; return r; });
  old.worker.reply("same", { bytes: new Uint8Array([1]) });
  old.worker.onerror?.();
  await Promise.resolve();
  expect(complete).toBe(false);
  replacement.worker.reply("same", { bytes: new Uint8Array([2]) });
  expect((await bounded(current)).bytes).toEqual(new Uint8Array([2]));
});

test("enqueue failure affects only that request; a pending live reply still completes", async () => {
  const s = make();
  const live = s.replies.request("live", {});
  s.worker.throws = true;
  expect((await bounded(s.replies.request("bad", {}))).error).toMatch(/enqueue/);
  expect(s.detached()).toBe(0);
  s.worker.reply("live", { error: "actual KiCad refusal" });
  expect(await bounded(live)).toEqual({ op: "reply", id: "live", error: "actual KiCad refusal" });
});

test("unmatched and duplicate replies never finish another request", async () => {
  const s = make();
  let complete = false;
  const reply = s.replies.request("wanted", {}).then((r) => { complete = true; return r; });
  s.worker.reply("other", { bytes: new Uint8Array([0]) });
  expect((await s.replies.request("wanted", {})).error).toMatch(/duplicate/);
  await Promise.resolve();
  expect(complete).toBe(false);
  s.worker.reply("wanted", { bytes: new Uint8Array([9]) });
  const result = await bounded(reply);
  s.worker.reply("wanted", { error: "late duplicate" });
  expect(result.bytes).toEqual(new Uint8Array([9]));
});

test.each(["exit", "error"])("actual Bun worker %s resolves its old wait while another worker still answers", async (op) => {
  const old = new Worker(new URL("./replies-worker.ts", import.meta.url));
  const live = new Worker(new URL("./replies-worker.ts", import.meta.url));
  let detached = 0;
  const before = new Replies(old, () => detached++);
  const current = new Replies(live, () => {});
  try {
    const waiting = before.request("old", { op: "wait", id: "old" });
    old.postMessage({ op });
    expect((await bounded(waiting)).error).toMatch(/worker.*outcome unknown/);
    expect(detached).toBe(1);
    const actual = current.request("live", { op: "reply", id: "live" });
    expect((await bounded(actual)).bytes).toEqual(new Uint8Array([42]));
  } finally {
    old.terminate();
    live.terminate();
  }
});
