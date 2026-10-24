// Server-only core/json.bend string byte counts. No cache, IO or mutation.
// for..of follows the reference's code-point slicing, including lone UTF-16
// surrogates. Count their three bytes directly; TextEncoder replaces them.
function __bpJsonBytesEsc(s, n, check) {
  for (const ch of s) {
    const c = ch.codePointAt(0);
    n = check(n + (c < 32 ? (c === 10 || c === 13 || c === 9 ? 2 : 6) :
      c === 34 || c === 92 ? 2 : c < 128 ? 1 : c < 2048 ? 2 : c < 65536 ? 3 : 4));
  }
  return n;
}

function __bpJsonBytesStr(s, n, check) {
  for (const ch of s) {
    const c = ch.codePointAt(0);
    n = check(n + (c < 128 ? 1 : c < 2048 ? 2 : c < 65536 ? 3 : 4));
  }
  return n;
}
