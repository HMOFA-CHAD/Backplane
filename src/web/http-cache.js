// A fresh noncredential query keeps an older installed service worker from
// matching a cached API response during its own update. The server still
// authenticates the ordinary path with the existing HttpOnly cookie.
export function freshEndpoint(path) {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return path + '?bpProbe=' + Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
}
export function jsonResponse(response) {
  return /^application\/json(?:\s*;|$)/i.test(response.headers?.get('content-type') || '');
}
export async function boundedText(response, limit) {
  if (Number(response.headers?.get('content-length')) > limit || !response.body?.getReader) throw Error('Invalid metadata response');
  const reader = response.body.getReader(), decoder = new TextDecoder('utf-8', { fatal: true });
  let bytes = 0, text = '';
  try {
    while (true) {
      const next = await reader.read();if (next.done) break;
      bytes += next.value.byteLength;
      if (bytes > limit) { void reader.cancel().catch(() => {});throw Error('Metadata response limit'); }
      text += decoder.decode(next.value, { stream: true });
    }
    return text + decoder.decode();
  } finally { reader.releaseLock(); }
}
