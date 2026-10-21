// Yield between ordered cache frames so restoring history cannot monopolize
// the browser's event loop. The caller connects only after this resolves.
function nextTask() {
  return new Promise(resolve => {
    const channel = new MessageChannel();
    const finish = () => {
      clearTimeout(timer);
      channel.port1.close();
      channel.port2.close();
      resolve();
    };
    // A lost channel notification must not strand history startup.
    const timer = setTimeout(finish, 100);
    channel.port1.onmessage = finish;
    channel.port2.postMessage(null);
  });
}

export async function replayFrames(frames, apply, {
  budgetMs = 8,
  now = () => performance.now(),
  yieldTask = nextTask,
  onYield = () => {},
  signal,
} = {}) {
  let started = now();
  for (let i = 0; i < frames.length; i += 1) {
    if (signal?.aborted) throw signal.reason;
    apply(frames[i]);
    if (i + 1 < frames.length && now() - started >= budgetMs) {
      onYield(i + 1);
      await yieldTask();
      started = now();
    }
  }
}

// A failed/late IndexedDB request never applies anything after this returns.
// During a replay timeout we wait for the loop to observe cancellation; a
// Promise.race around the loop would leave a second state writer alive.
export async function restoreCache(load, apply, { timeoutMs = 10000, ...options } = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(new Error('Cache restore deadline')), timeoutMs);
  let applied = 0;
  try {
    const frames = await new Promise((resolve, reject) => {
      controller.signal.addEventListener('abort', () => reject(controller.signal.reason), { once: true });
      Promise.resolve().then(load).then(resolve, reject);
    });
    await replayFrames(frames, frame => { apply(frame); applied += 1; }, { ...options, signal: controller.signal });
    return { applied, error: null };
  } catch (error) {
    return { applied, error };
  } finally {
    clearTimeout(timer);
  }
}
