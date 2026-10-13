#!/usr/bin/env python3
"""Hand a client's whole state across Bend's JS boundary as it is.

Bend 2.0.36's JS target keeps a Nat as a Number inside and hands it to JS
as a BigInt, so every exported def walks each argument and answer whose
type holds a Nat: in, out, and the argument back. The phones' bridge.js
and the web's host.js keep the client's whole state (every hub's log) and
hand it to every call, so each frame, each keystroke, rebuilt all of it
several times; a phone's cold join went quadratic (a real log: 93 s with
no JIT instead of 12, minutes of an empty list on an iPhone). The JS side
never looks inside that state, only hands it back, so both marshallers of
its type answer their value and it stays in Bend's own form (Numbers).
They are found by the shape Bend emits them in, for the constructor named
(as the loading file sees it); a bundle where there are not exactly two
stops the build rather than ship without it.

  scripts/js-unmarshal.py TAG FILE...
  scripts/js-unmarshal.py hubs.Hubs mobile/build/assets/bridge.js
  scripts/js-unmarshal.py ../core/client.Ui dist/web/chunk-*.js
"""
import re
import sys

tag, files = sys.argv[1], sys.argv[2:]
I = r"[A-Za-z0-9_$]+"
marsh = re.compile(
    r'function (' + I + r')\(([A-Za-z])\)\{let [A-Za-z]=\[\2\];for\(let [A-Za-z]=[A-Za-z],[A-Za-z]=0;;\)switch\(\2\.\$\)\{case"' + re.escape(tag) + r'":'
)
srcs = {f: open(f, encoding="utf-8").read() for f in files}
found = sum(len(marsh.findall(s)) for s in srcs.values())
if found != 2:
    sys.exit(f"js-unmarshal: {tag}'s marshallers found {found} times, not twice")
names = []
for f, src in srcs.items():
    hs = list(marsh.finditer(src))
    for h in reversed(hs):
        # the old body ends where the next top-level function starts
        end = src.index("}function ", h.end()) + 1
        while src[h.start():end].count("{") != src[h.start():end].count("}"):
            end = src.index("}function ", end) + 1
        src = src[: h.start()] + f"function {h.group(1)}(v){{return v}}" + src[end:]
        names.append(h.group(1))
    if hs:
        open(f, "w", encoding="utf-8").write(src)
print(f"js-unmarshal: {tag} ({', '.join(sorted(names))}) crosses as it is")
