'use strict';

// Private main/service messages only. JSON.parse alone silently accepts repeated
// object keys, including escaped spellings of a previous key. Validate the token
// structure before parsing, with fixed resource bounds for untrusted CDP results.
const MAX_BYTES = 1024 * 1024;
function decodeBrowserMessage(input) {
  const bytes = typeof input === 'string' ? Buffer.from(input, 'utf8') : input;
  if (!Buffer.isBuffer(bytes) || bytes.length > MAX_BYTES) throw new TypeError('Invalid Browser frame size');
  const source = new TextDecoder('utf-8', {fatal:true}).decode(bytes);
  let cursor = 0, tokens = 0;
  const fail = () => { throw new TypeError('Invalid Browser JSON'); };
  function space() { while (/[\x20\x09\x0a\x0d]/.test(source[cursor] ?? '\x00')) cursor++; }
  function string() {
    if (source[cursor] !== '"') fail();
    const start = cursor++;
    while (cursor < source.length) {
      const code = source.charCodeAt(cursor++);
      if (code === 34) return JSON.parse(source.slice(start,cursor));
      if (code < 32) fail();
      if (code === 92) {
        const escaped = source[cursor++];
        if (escaped === 'u') {
          if (!/^[a-fA-F0-9]{4}$/.test(source.slice(cursor,cursor+4))) fail();
          cursor += 4;
        } else if (!['"','\\','/','b','f','n','r','t'].includes(escaped)) fail();
      }
    }
    fail();
  }
  function value(depth) {
    if (depth > 64 || ++tokens > 65536) fail();
    space();
    const first = source[cursor];
    if (first === '{' || first === '[') {
      const object = first === '{', end = object ? '}' : ']';
      const keys = object ? new Set() : null;
      cursor++; space();
      if (source[cursor] === end) {cursor++; return;}
      for (;;) {
        if (object) {
          const key = string();
          if (keys.has(key)) fail();
          keys.add(key); space();
          if (source[cursor++] !== ':') fail();
        }
        value(depth+1); space();
        const separator = source[cursor++];
        if (separator === end) return;
        if (separator !== ',') fail();
        space();
      }
    }
    if (first === '"') {string(); return;}
    for (const literal of ['true','false','null']) {
      if (source.startsWith(literal,cursor)) {cursor+=literal.length; return;}
    }
    const number = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/.exec(source.slice(cursor));
    if (!number || !Number.isFinite(Number(number[0]))) fail();
    cursor+=number[0].length;
  }
  value(0); space();
  if (cursor !== source.length) fail();
  const parsed = JSON.parse(source);
  if (!parsed || Object.getPrototypeOf(parsed) !== Object.prototype) fail();
  return parsed;
}

function exactObject(value, required, optional=[]) {
  if (!value || Object.getPrototypeOf(value) !== Object.prototype ||
      required.some(key=>!Object.hasOwn(value,key)) ||
      Object.keys(value).some(key=>!required.includes(key)&&!optional.includes(key))) throw new TypeError('Invalid Browser message fields');
  return value;
}
function encodeBrowserMessage(value){
  const source=JSON.stringify(value,(_key,item)=>{
    if((typeof item==='number'&&!Number.isFinite(item))||['undefined','function','symbol','bigint'].includes(typeof item))throw new TypeError('Invalid Browser JSON value');
    if(item!==null&&typeof item==='object'&&!Array.isArray(item)&&Object.getPrototypeOf(item)!==Object.prototype)throw new TypeError('Invalid Browser JSON object');
    return item;
  });
  // Validate our own depth, node and byte bounds before allocating a WS frame.
  decodeBrowserMessage(source);
  return source;
}
function targetKey(target) {
  exactObject(target,['owner','tabId','generation']);
  for (const key of ['owner','tabId']) if (typeof target[key] !== 'string' || !target[key].length || target[key].length>512 || /[\x00-\x1f]/.test(target[key])) throw new TypeError('Invalid Browser target');
  if (!Number.isSafeInteger(target.generation) || target.generation<0) throw new TypeError('Invalid Browser generation');
  // Structured encoding avoids owner/tab delimiter collisions.
  return JSON.stringify([target.owner,target.tabId,target.generation]);
}
module.exports={decodeBrowserMessage,encodeBrowserMessage,exactObject,targetKey,MAX_BYTES};
