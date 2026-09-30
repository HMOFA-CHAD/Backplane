#!/usr/bin/env python3
# The phone apps keep the Bend client's whole state between launches, as
# the JSON of its values (a constructor per object, its fields by name).
# That shape comes only from the Bend type definitions (and Base's, so the
# bend version), not from the code around them: this hash names the kept
# state, so a build that changes only code keeps it and one that changes
# a type it holds starts afresh (and asks every hub for its whole log).
# Only the types the kept value (hubs.bend's Hubs) can hold count: from
# Hubs, every type a field names, through the files' imports, and so on;
# a type the phones never keep (the hub's, the window's) changes nothing.
#   python3 scripts/state-key.py          -> 16 hex digits
#   python3 scripts/state-key.py --types  -> the types it covers
import hashlib, os, re, subprocess, sys

root = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
ROOT_FILE = os.path.join(root, "src", "mobile", "hubs.bend")
ROOT_TYPE = "Hubs"

# every file's type blocks (by name) and imports (by alias)
types = {}
imports = {}


def load(path):
    if path in types:
        return
    types[path] = {}
    imports[path] = {}
    lines = open(path, encoding="utf-8").read().split("\n")
    i = 0
    while i < len(lines):
        m = re.match(r"import (\S+\.bend) as (\S+)", lines[i])
        if m:
            imports[path][m.group(2)] = os.path.normpath(os.path.join(os.path.dirname(path), m.group(1)))
        m = re.match(r"type ([A-Za-z_][\w.]*)", lines[i])
        if m:
            block = [lines[i].rstrip()]
            i += 1
            while i < len(lines) and (lines[i].startswith(" ") or not lines[i].strip()):
                if lines[i].strip() and not lines[i].strip().startswith("#"):
                    block.append(lines[i].rstrip())
                i += 1
            types[path][m.group(1)] = "\n".join(block) + "\n"
        else:
            i += 1


seen = set()
todo = [(ROOT_FILE, ROOT_TYPE)]
while todo:
    path, name = todo.pop()
    if (path, name) in seen:
        continue
    load(path)
    block = types[path].get(name)
    if block is None:
        continue
    seen.add((path, name))
    # the constructors' fields: every type name after a colon or inside <>
    body = block.split("\n", 1)[1]
    for tok in re.findall(r"[A-Za-z_][\w]*(?:\.[A-Za-z_][\w]*)*", body):
        parts = tok.split(".")
        if len(parts) > 1 and parts[0] in imports[path]:
            target = imports[path][parts[0]]
            load(target)
            todo.append((target, ".".join(parts[1:])))
        else:
            todo.append((path, tok))
    # a type's own head names its parameters' kinds and itself
    head = block.split("\n", 1)[0]
    for tok in re.findall(r"[A-Za-z_][\w]*\.[A-Za-z_][\w]*", head):
        a, b = tok.split(".", 1)
        if a in imports[path]:
            target = imports[path][a]
            load(target)
            todo.append((target, b))

if not any(n == ROOT_TYPE for _, n in seen):
    sys.exit("state-key: no type Hubs in src/mobile/hubs.bend")

h = hashlib.sha256()
try:
    h.update(subprocess.run(["bend", "version"], capture_output=True, text=True).stdout.split("\n")[0].encode())
except OSError:
    pass
kept = sorted(seen, key=lambda pn: (os.path.relpath(pn[0], root), pn[1]))
for path, name in kept:
    h.update((os.path.relpath(path, root) + "\n" + types[path][name]).encode())
if sys.argv[1:] == ["--types"]:
    for path, name in kept:
        print(os.path.relpath(path, root), name)
else:
    sys.stdout.write(h.hexdigest()[:16] + "\n")
