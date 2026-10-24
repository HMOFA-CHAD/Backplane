// Server-only core/json.bend Json.show. No cache, mutation or IO.
function __bpJsonQuote(s) {
  return '"' + s.replace(/[\x00-\x1f"\\\ud800-\udfff]/gu, c => {
    const n = c.charCodeAt(0);
    // Bend's char_new rejects an unpaired surrogate by throwing this string.
    // Unicode regex mode leaves valid surrogate pairs together.
    if (n >= 0xd800 && n <= 0xdfff)
      throw "bend: " + n + " is not a Unicode scalar value";
    return c === '"' ? '\\"' : c === '\\' ? '\\\\' :
      c === '\n' ? '\\n' : c === '\r' ? '\\r' : c === '\t' ? '\\t' :
      '\\u00' + n.toString(16).padStart(2, '0');
  }) + '"';
}

function __bpJsonShow(j, fallback) {
  const parts = [], stack = [{j, first: true}];
  while (stack.length) {
    const frame = stack.pop();
    if (typeof frame === 'string') { parts.push(frame); continue; }
    const x = frame.j, kind = x.$.slice(x.$.lastIndexOf('.') + 1);
    switch (kind) {
      case 'Null': parts.push('null'); break;
      case 'Flag': parts.push(x.value ? 'true' : 'false'); break;
      case 'Num':
        // Num.raw is deliberately not parsed or reformatted. For non-ASCII
        // lexemes retain even the reference's unusual reversal boundaries.
        if (/[^\x00-\x7f]/.test(x.raw)) return fallback(j);
        parts.push(x.raw); break;
      case 'Str': parts.push(__bpJsonQuote(x.text)); break;
      case 'Arr': parts.push('['); stack.push(']', {j: x.items, first: true}); break;
      case 'Obj': parts.push('{'); stack.push('}', {j: x.fields, first: true}); break;
      case 'Item':
        if (!frame.first) parts.push(',');
        stack.push({j: x.tail, first: false}, {j: x.head, first: true}); break;
      case 'Field':
        if (!frame.first) parts.push(',');
        parts.push(__bpJsonQuote(x.key), ':');
        stack.push({j: x.tail, first: false}, {j: x.value, first: true}); break;
      case 'End': break;
      default: return fallback(j);
    }
  }
  return parts.join('');
}
