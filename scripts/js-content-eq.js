// Server-only exact structural JSON equality. Identity is a sufficient
// equality proof for immutable Bend values; no key/hash or cache is involved.
function __bpContentEq(a, b, fallback) {
  const todo = [[a, b]];
  while (todo.length) {
    const [a, b] = todo.pop();
    if (a === b) continue;
    if (a.$ !== b.$) return false;
    switch (a.$.slice(a.$.lastIndexOf('.') + 1)) {
      case 'Null': case 'End': break;
      case 'Flag': if (a.value !== b.value) return false; break;
      case 'Num': if (a.raw !== b.raw) return false; break;
      case 'Str': if (a.text !== b.text) return false; break;
      case 'Arr': todo.push([a.items, b.items]); break;
      case 'Obj': todo.push([a.fields, b.fields]); break;
      case 'Item': todo.push([a.tail, b.tail], [a.head, b.head]); break;
      case 'Field':
        if (a.key !== b.key) return false;
        todo.push([a.tail, b.tail], [a.value, b.value]); break;
      default: return fallback(a, b);
    }
  }
  return true;
}
