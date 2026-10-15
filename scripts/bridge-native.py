#!/usr/bin/env python3
"""Give the phones' bundle native string comparisons.

Bend's JS target compares strings as Base defines them: a char at a time,
each step a slice of both strings, a Char.cmp and a tuple built on the way
back. On a phone's JavaScriptCore or QuickJS (no JIT) that was over half of
every screen (a list of 126 threads: 150 ms, 60 ms with these). The
replacements answer exactly what Base's String.cmp and String.eq do (the
strings back unchanged, the order by code point), found by the shape Bend
emits them in; a bundle where they are not found stops the build rather
than ship without them.

  scripts/bridge-native.py mobile/build/assets/bridge.js
"""
import re
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()

I = r"[A-Za-z0-9_$]+"

# String.cmp: (a, b) -> ((a, b), Cmp)
cmp_head = re.compile(
    r'function (' + I + r')\(([A-Z]),([A-Z])\)\{if\(\2===""\)if\(\3===""\)return\{\$:"Tuple",fst:\{\$:"Tuple",fst:"",snd:""\},snd:\{\$:"EQ"\}\};'
)
ms = list(cmp_head.finditer(src))
if len(ms) != 1:
    sys.exit(f"bridge-native: String.cmp found {len(ms)} times, not once")
m = ms[0]
cmp = m.group(1)
# the old body ends where the next top-level function starts
end = src.index("}function ", m.end()) + 1
while src[m.start():end].count("{") != src[m.start():end].count("}"):
    end = src.index("}function ", end) + 1
native_cmp = (
    f"function {cmp}(a,b){{let r;if(a===b)r=\"EQ\";else{{let i=0;const n=a.length<b.length?a.length:b.length;"
    "while(i<n&&a.charCodeAt(i)===b.charCodeAt(i))i++;"
    "r=i===n?(a.length<b.length?\"LT\":\"GT\"):(a.codePointAt(i)<b.codePointAt(i)?\"LT\":\"GT\")}"
    "return{$:\"Tuple\",fst:{$:\"Tuple\",fst:a,snd:b},snd:{$:r}}}"
)
src = src[: m.start()] + native_cmp + src[end:]

# Cmp.is_eq: EQ true, anything else false
is_eq = re.findall(r'function (' + I + r')\(([A-Z])\)\{if\(\2\.\$==="EQ"\)return!0;else return!1\}', src)
names = {n for n, _ in is_eq}
# String.eq is Cmp.is_eq(String.order(a, b)), String.order the snd of String.cmp
snd = {n for n, _ in re.findall(r'function (' + I + r')\(([A-Z])\)\{return \2\.snd\}', src)}
orders = {
    m_.group(1)
    for m_ in re.finditer(r'function (' + I + r')\(([A-Z]),([A-Z])\)\{return (' + I + r')\(' + re.escape(cmp) + r'\(\2,\3\)\)\}', src)
    if m_.group(4) in snd
}
eqs = [
    m_
    for m_ in re.finditer(r'function (' + I + r')\(([A-Z]),([A-Z])\)\{return (' + I + r')\((' + I + r')\(\2,\3\)\)\}', src)
    if m_.group(4) in names and m_.group(5) in orders
]
if len(eqs) != 1:
    sys.exit(f"bridge-native: String.eq found {len(eqs)} times, not once")
e = eqs[0]
src = src[: e.start()] + f"function {e.group(1)}(a,b){{return a===b}}" + src[e.end():]

# Map.bit(key, pos): the key back and bit pos of it, 33 bits a code point
# (the first says the code point is there, then its 32 bits, highest
# first); a key too short has none. Bend's walks the key a code point at a
# time, a slice each, and builds it again on the way back: every Map.get,
# Map.set and Map.has does it once a level, most of a phone's screen.
# Found as the def Bend emits: Map.bit.at(key, Nat.divmod(pos, 33)).
divmod = re.findall(r'function (' + I + r')\(([A-Z]),([A-Z])\)\{return \3===0\?\{\$:"Tuple",fst:0,snd:\2\}:\{\$:"Tuple",fst:Math\.trunc\(\2/\3\),snd:\2%\3\}\}', src)
if len(divmod) != 1:
    sys.exit(f"bridge-native: Nat.divmod found {len(divmod)} times, not once")
bits = list(re.finditer(r'function (' + I + r')\(([A-Z]),([A-Z])\)\{return (' + I + r')\(\2,' + re.escape(divmod[0][0]) + r'\(\3,33\)\)\}', src))
if len(bits) != 1:
    sys.exit(f"bridge-native: Map.bit found {len(bits)} times, not once")
b = bits[0]
native_bit = (
    f"function {b.group(1)}(k,p){{const ci=Math.trunc(p/33),off=p%33;let i=0;"
    "for(let n=0;n<ci&&i<k.length;n++)i+=k.codePointAt(i)>65535?2:1;"
    "const h=i<k.length&&(off===0||((k.codePointAt(i)>>>(32-off))&1)!==0);"
    "return{$:\"Tuple\",fst:k,snd:h}}"
)
src = src[: b.start()] + native_bit + src[b.end():]

# String.starts_with(s, p) and String.contains(s, p), a code point at a
# time in Bend (contains tries starts_with at every code point: a long
# reply's markdown asked contains(text, "/") of every run of text, the most
# of a streamed thread's screen). Natively the same answers: JavaScript
# compares UTF-16 units, so a match that ends between the two halves of a
# surrogate pair in s (p ending with a lone high surrogate), or for contains
# starts between them, is not one, as it is not code point by code point.
sw = re.compile(
    r'function (' + I + r')\(([A-Z]),([A-Z]),([A-Z])\)\{let ([A-Z])=0;for\(;;\)switch\(\5\)\{case 0:\{let ([A-Z])=\2,([A-Z])=\3;'
    r'if\(\6===""\)if\(\7===""\)return!0;else return!1;else\{'
)
sws = list(sw.finditer(src))
if len(sws) != 1:
    sys.exit(f"bridge-native: String.starts_with found {len(sws)} times, not once")
swn = sws[0].group(1)
def body_end(src, start):
    end = src.index("}function ", start) + 1
    while src[start:end].count("{") != src[start:end].count("}"):
        end = src.index("}function ", end) + 1
    return end
SUR = "const hi=c=>c>=55296&&c<56320,lo=c=>c>=56320&&c<57344;"
src = src[: sws[0].start()] + (
    f"function {swn}(s,p){{{SUR}return s.startsWith(p)&&!(p.length>0&&hi(p.charCodeAt(p.length-1))&&lo(s.charCodeAt(p.length)))}}"
) + src[body_end(src, sws[0].start()):]
ct = re.compile(
    r'function (' + I + r')\(([A-Z]),([A-Z]),([A-Z])\)\{let ([A-Z])=0;for\(;;\)switch\(\5\)\{case 0:\{let ([A-Z])=\2,([A-Z])=\3;if\(\6===""\)return ' + I +
    r'\(\7\);else\{[^{}]*' + re.escape(swn) + r'\(([A-Z])\+([A-Z]),\7\),\5=1;continue\}\}case 1:'
)
cts = list(ct.finditer(src))
if len(cts) != 1:
    sys.exit(f"bridge-native: String.contains found {len(cts)} times, not once")
ctn = cts[0].group(1)
src = src[: cts[0].start()] + (
    "function " + ctn + "(s,p){" + SUR + 'if(p==="")return!0;for(let f=0;;){const i=s.indexOf(p,f);if(i<0)return!1;'
    "if(!((i>0&&lo(s.charCodeAt(i))&&hi(s.charCodeAt(i-1)))||(hi(p.charCodeAt(p.length-1))&&lo(s.charCodeAt(i+p.length)))))return!0;f=i+1}}"
) + src[body_end(src, cts[0].start()):]

# Pure defs of one string asked again and again with the same few strings:
# their answers are kept (a def of a value answers the same every time).
# Hubs's Q.kind: what each key of a screen holds, asked for every field of
# every screen (the key set is the screen's field names). A def is found by
# its entry in the bundle's table of exported defs ("name":wrapper((M)=>{...}))
# as the innermost call on its argument.
def internal(src, name):
    m = re.search(r'"' + re.escape(name) + r'":' + I + r'\(\(([A-Z])\)=>\{([^{}]*)\}', src)
    if not m:
        sys.exit(f"bridge-native: {name} not found in the table of defs")
    calls = list(re.finditer(r'(?<![\w$])(?=(' + I + r')\((?:' + I + r'\()?' + m.group(1) + r'\))', m.group(2)))
    if not calls:
        sys.exit(f"bridge-native: {name}'s def not found in its entry")
    return calls[-1].group(1)
kept = []
for name in ["hubs.Q.kind"]:
    fn = internal(src, name)
    head = re.compile(r'(?<![\w$.])function ' + re.escape(fn) + r'\(')
    if len(head.findall(src)) != 1:
        sys.exit(f"bridge-native: {name} ({fn}) defined {len(head.findall(src))} times, not once")
    at = head.search(src)
    end = body_end(src, at.start())
    raw = fn + "$raw"
    src = (src[: at.start()] + "function " + raw + "(" + src[at.end(): end] +
        f"var {fn}$kept;function {fn}(k){{const m={fn}$kept??({fn}$kept=new Map());let v=m.get(k);if(v===void 0){{if(m.size>4096)m.clear();v={raw}(k);m.set(k,v)}}return v}}" + src[end:])
    kept.append(f"{name} ({fn})")
print("bridge-native: answers kept for " + ", ".join(kept))

# A def the minifier named after a global JavaScript will not let a script
# redeclare (NaN, Infinity, undefined) stops the whole bundle loading in
# JavaScriptCore and V8 ("Can't declare global function 'NaN'"). Such a
# name is only ever called (the real values are never called), so the calls
# and the declaration are renamed together.
for g in ("NaN", "Infinity", "undefined"):
    n = len(re.findall(r'(?<![\w$.])' + g + r'\(', src))
    if n:
        src = re.sub(r'(?<![\w$.])' + g + r'\(', g + "$b(", src)
        print(f"bridge-native: a def named {g} renamed ({n} places)")

open(path, "w", encoding="utf-8").write(src)
print(f"bridge-native: String.cmp ({cmp}), String.eq ({e.group(1)}), Map.bit ({b.group(1)}), String.starts_with ({swn}), String.contains ({ctn}) native")
