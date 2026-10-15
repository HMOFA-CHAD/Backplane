#!/usr/bin/env python3
"""Base's string primitives as JavaScript's own, in a minified JS bundle.

Bend 2.0.36's JS target compares strings the way its Bend source reads
(`String.cmp`: a code point at a time, each step slicing off a fresh tail
and rebuilding both strings on the way out), so every `String.eq`, every
`Map.get`/`Map.set` on a String key (`Map.bit`: walks to the key's char by
slicing too) costs allocations quadratic in the strings' lengths. In the web
client that was a third of every frame. This replaces the bodies of those
defs with the same answers computed natively:

- `String.cmp(a, b)`: `((a, b), order)`, the order by code points (the
  strings it hands back are the ones it was given, as Bend's rebuild them)
- `Map.bit.go(key, ci, off)`: `(key, bit)`, the bit of the key's code point
  `ci` at offset `off` (0 is "there is such a char"; else bit 31-(off-1)),
  false past the key's end

Each is found by its shape and must be found exactly once, else the build
stops (a new Bend that emits them otherwise needs this looked at again).
`bun test/tools/js_native_test.ts` checks both against Base's definitions.

  scripts/js-native.py dist/web/chunk-*.js
"""
import re
import sys

I = r"[A-Za-z0-9_$]+"

# the helpers the new bodies call, put before everything else in the file
HELPERS = (
    "function __bpOrd(a,b){if(a===b)return\"EQ\";const n=Math.min(a.length,b.length);let i=0;"
    "while(i<n&&a.charCodeAt(i)===b.charCodeAt(i))i++;if(i===n)return a.length<b.length?\"LT\":\"GT\";"
    "return a.codePointAt(i)<b.codePointAt(i)?\"LT\":\"GT\"}"
    "function __bpBit(k,ci,off){let n=0;for(const c of k){if(n===ci){if(off===0)return true;"
    "return((c.codePointAt(0)>>>(31-(off-1)))&1)!==0}n++}return false}\n"
)

# String.cmp: function F(a,b){if(a==="")if(b==="")return{$:"Tuple",fst:{$:"Tuple",fst:"",snd:""},snd:{$:"EQ"}};...
CMP = re.compile(
    r'function (' + I + r')\((' + I + r'),(' + I + r')\)\{(?=if\(\2===""\)if\(\3===""\)return\{\$:"Tuple",fst:\{\$:"Tuple",fst:"",snd:""\},snd:\{\$:"EQ"\}\};)'
)
# Map.bit.go: function F(k,ci,off){if(k==="")return{$:"Tuple",fst:"",snd:!1};else{let c=k.codePointAt(0)>65535?k.slice(0,2):k[0],t=...;if(ci===0)
BIT = re.compile(
    r'function (' + I + r')\((' + I + r'),(' + I + r'),(' + I + r')\)\{(?=if\(\2===""\)return\{\$:"Tuple",fst:"",snd:!1\};else\{let ' + I + r'=\2\.codePointAt\(0\)>65535\?\2\.slice\(0,2\):\2\[0\],' + I + r'=\2\.codePointAt\(0\)>65535\?\2\.slice\(2\):\2\.slice\(1\);if\(\3===0\))'
)

files = sys.argv[1:]
srcs = {f: open(f, encoding="utf-8").read() for f in files}
for name, rx in (("String.cmp", CMP), ("Map.bit.go", BIT)):
    n = sum(len(rx.findall(s)) for s in srcs.values())
    if n != 1:
        sys.exit(f"js-native: {name} found {n} times, not once")
for f, s in srcs.items():
    hit = CMP.search(s) or BIT.search(s)
    if not hit:
        continue
    s = CMP.sub(lambda m: m.group(0) + 'return{$:"Tuple",fst:{$:"Tuple",fst:%s,snd:%s},snd:{$:__bpOrd(%s,%s)}};' % (m.group(2), m.group(3), m.group(2), m.group(3)), s)
    s = BIT.sub(lambda m: m.group(0) + 'return{$:"Tuple",fst:%s,snd:__bpBit(%s,%s,%s)};' % (m.group(2), m.group(2), m.group(3), m.group(4)), s)
    # (a module's imports may come after it: they are hoisted)
    s = HELPERS + s
    open(f, "w", encoding="utf-8").write(s)
print("js-native: String.cmp and Map.bit.go are native")
