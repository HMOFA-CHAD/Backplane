#!/usr/bin/env python3
# The files a Bend program reads from the checkout: the roots, every .bend
# they import (transitively), the effect files they import ("./x.c",
# "./x.js") and the local headers those include (#include "y.h").
#
#   scripts/bend-closure.py ROOT.bend...    one path per line, sorted
#
# It fails closed: an import line it does not understand, or a file it
# cannot read, exits 1 with nothing printed, so a key built from it is never
# taken for one that covers less than bend reads.
import os
import re
import sys

BEND = re.compile(r'^\s*import\s+(\S+)(?:\s+as\s+[A-Za-z_][A-Za-z0-9_]*)?\s*(?:#.*)?$')
INCL = re.compile(r'^\s*#\s*include\s+"([^"]+)"')


def die(msg):
    sys.stderr.write("bend-closure: %s\n" % msg)
    sys.exit(1)


def rel(p):
    return os.path.relpath(os.path.normpath(p))


seen, todo = set(), [rel(r) for r in sys.argv[1:]]
if not todo:
    die("no roots")
while todo:
    f = todo.pop()
    if f in seen:
        continue
    if f.startswith("..") or os.path.isabs(f):
        die("outside the checkout: %s" % f)
    seen.add(f)
    try:
        text = open(f, encoding="utf-8").read()
    except OSError as e:
        die("cannot read %s: %s" % (f, e))
    here = os.path.dirname(f)
    if f.endswith(".bend"):
        for line in text.split("\n"):
            if not re.match(r"^\s*import\b", line):
                continue
            m = BEND.match(line)
            if not m:
                die("%s: an import it does not understand: %r" % (f, line))
            name = m.group(1)
            if name.startswith('"') and name.endswith('"'):
                name = name[1:-1]
            if name.startswith("./") or name.startswith("../"):
                todo.append(rel(os.path.join(here, name)))
            elif not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", name):
                die("%s: an import it does not understand: %r" % (f, line))
            # a bare name (Base, a named library) is bend's own: the key
            # covers bend's files separately
    elif f.endswith((".c", ".h")):
        for line in text.split("\n"):
            m = INCL.match(line)
            if m:
                p = rel(os.path.join(here, m.group(1)))
                if os.path.exists(p):
                    todo.append(p)
                # a quoted include that is not beside it is a generated
                # header (bp_google.h, bp_telemetry.h) or a system one
for f in sorted(seen):
    print(f)
