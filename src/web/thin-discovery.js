// Platform HTTP IO only. The shared transport owns protocol validation.
import { freshEndpoint, jsonResponse, boundedText } from './http-cache.js';
export async function discoverViews({ fetch, validate, timeoutMs = 2000 }) {
  const abort = new AbortController();let timer;
  const limit = 16384;
  try {
    return await Promise.race([
      (async () => {
        const response = await fetch(freshEndpoint('/client/capabilities'), { credentials: 'same-origin', cache: 'no-store', signal: abort.signal });
        if (response.status !== 200 || !jsonResponse(response)) return { supported: false };
        const capability = JSON.parse(await boundedText(response, limit));
        return { supported: validate(capability) === true };
      })().catch(() => ({ supported: false })),
      new Promise(resolve => { timer = setTimeout(() => { abort.abort();resolve({ supported: false }); }, timeoutMs); }),
    ]);
  } finally { clearTimeout(timer); }
}
