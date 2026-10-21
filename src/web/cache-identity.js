import { cacheIdentity } from './focused-cache.js';
import { freshEndpoint, jsonResponse, boundedText } from './http-cache.js';

// This public tag partitions a local read-only picture. It is never a
// credential, request authorization, replay cursor or proof of readiness.
export async function refreshCacheIdentity({ fetch, readCookie, writeCookie, protocol, timeoutMs = 1500 }) {
  const initial = cacheIdentity(readCookie());
  const controller = new AbortController();
  let timer;
  const cookie = (key, age) => writeCookie(`bp_cache_v1=${key}; Path=/; SameSite=Strict; Max-Age=${age}${protocol === 'https:' ? '; Secure' : ''}`);
  try {
    const response = await Promise.race([
      Promise.resolve().then(async () => {
        const r = await fetch(freshEndpoint('/auth/cache'), { credentials: 'same-origin', cache: 'no-store', signal: controller.signal });
        if (r.status === 401 || r.status === 403) return { state: 'denied' };
        if (r.status !== 200) return { state: 'offline' };
        // An old worker's offline root-HTML fallback is not identity evidence.
        if (!jsonResponse(r)) return { state: 'offline' };
        let text;try { text = await boundedText(r, 256); } catch { return { state: 'invalid' }; }
        const body = JSON.parse(text);
        if (body?.version !== 1 || typeof body.cacheKey !== 'string' || !/^[0-9a-f]{64}$/.test(body.cacheKey)
          || Object.keys(body).sort().join(',') !== 'cacheKey,version') return { state: 'invalid' };
        return { state: 'verified', identity: body.cacheKey };
      }),
      new Promise(resolve => { timer = setTimeout(() => { controller.abort(); resolve({ state: 'offline' }); }, timeoutMs); }),
    ]);
    // Pairing or another tab changed the profile while this request travelled.
    // Its eventual response must not overwrite the newer partition.
    if (cacheIdentity(readCookie()) !== initial) return { state: 'superseded', identity: cacheIdentity(readCookie()) };
    if (response.state === 'verified') cookie(response.identity, 31536000);
    else if (response.state === 'denied' || response.state === 'invalid') cookie('', 0);
    return { state: response.state, identity: cacheIdentity(readCookie()) };
  } catch (error) {
    // Offline restores retain the existing read-only partition; a malformed
    // authenticated response is suppressed rather than used as an identity.
    const state = error instanceof SyntaxError ? 'invalid' : 'offline';
    if (state === 'invalid' && cacheIdentity(readCookie()) === initial) cookie('', 0);
    return { state, identity: cacheIdentity(readCookie()) };
  } finally { clearTimeout(timer); }
}
