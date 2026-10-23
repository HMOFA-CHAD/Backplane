// Inspect only envelope scalars before the payload. The rejected frame is
// never decoded, copied or retained; diagnostics contain fixed enums only.
const TYPES = new Set(['reply','view','hb','view.changed','plot','term','shot','info','log','changes','delta']);
export function frameSummary(bytes, keys, words) {
  const end = Math.min(bytes.length, 1024);
  let at = 0, type = 'unknown', id;
  const byte = () => { if (at >= end) throw Error('header boundary');return bytes[at++]; };
  const argument = ai => {
    if (ai < 24) return ai;
    const count = ai === 24 ? 1 : ai === 25 ? 2 : ai === 26 ? 4 : 0;
    if (!count) throw Error('unsupported header');
    let n = 0;for (let i = 0; i < count; i++) n = n * 256 + byte();return n;
  };
  const scalar = (tag = 0) => {
    const head = byte(), major = head >> 5, n = argument(head & 31);
    if (major === 6 && tag === 0 && (n === 6 || n === 7)) return scalar(n);
    if (major === 0 && tag === 0) return n;
    if (major === 0 && tag === 6) return words[n];
    if (major === 3 && (tag === 0 || tag === 7)) {
      if (n > 64 || at + n > end) throw Error('payload boundary');
      let text = '';for (let i = 0; i < n; i++) { const c = byte();if (c > 127) throw Error('non-metadata text');text += String.fromCharCode(c); }
      return tag === 7 && /^(0|[1-9][0-9]{0,15})$/.test(text) ? Number(text) : tag === 0 ? text : undefined;
    }
    if (major === 7 && tag === 0 && (n === 20 || n === 21)) return n === 21;
    throw Error('payload boundary');
  };
  try {
    const head = byte();if ((head >> 5) !== 5) throw Error('not an envelope');
    const count = argument(head & 31);
    for (let i = 0; i < Math.min(count, 12); i++) {
      const raw = scalar(), key = typeof raw === 'number' ? keys[raw] : raw;
      if (!['t','id','ok'].includes(key)) break;
      const value = scalar();
      if (key === 't' && TYPES.has(value)) type = value;
      if (key === 'id' && Number.isSafeInteger(value) && value >= 0) id = value;
    }
  } catch { /* A partial or unfamiliar header stays explicitly unclassified. */ }
  const frameClass = type === 'reply' ? id === undefined ? 'unknown-reply' : id >= 2 ** 47 ? 'view-reply' : 'ordinary-reply'
    : type === 'unknown' ? 'unknown' : 'notification';
  return { frameType: type, frameClass };
}
