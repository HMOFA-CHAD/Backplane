#!/usr/bin/env python3
"""Shard test programs by recorded duration for scripts/test.sh and CI.

Usage: test-shard.py TIMINGS SHARD COUNT TEST...

Prints, one per line, the tests assigned to SHARD (1-based) of COUNT,
in the original (alphabetical) order given on the command line.
Assignment is longest-first greedy over the durations in TIMINGS
(lines: "<seconds> <path>", '#' comments allowed): each test, longest
first, goes to the shard with the smallest assigned total so far.
A test missing from TIMINGS is treated as unknown: unknowns are placed
after all timed tests, in name order, by the same greedy rule with the
median recorded duration, so a new test always runs in exactly one
shard. Before printing, the full partition is verified: every given
test appears in exactly one shard, and the script exits non-zero
otherwise. With COUNT=1 every test is printed.
"""
import statistics
import sys


def load_timings(path):
    times = {}
    try:
        rows = open(path).read().splitlines()
    except OSError:
        return times
    for row in rows:
        row = row.strip()
        if not row or row.startswith("#"):
            continue
        secs, _, name = row.partition(" ")
        try:
            times[name.strip()] = float(secs)
        except ValueError:
            continue
    return times


def partition(tests, times, count):
    if count <= 1:
        return [list(tests)]
    known = sorted((t for t in tests if t in times), key=lambda t: (-times[t], t))
    unknown = sorted(t for t in tests if t not in times)
    fill = statistics.median(times.values()) if times else 1.0
    dur = {t: times.get(t, fill) for t in tests}
    groups = [[] for _ in range(count)]
    totals = [0.0] * count
    for t in known + unknown:
        i = min(range(count), key=lambda j: (totals[j], j))
        groups[i].append(t)
        totals[i] += dur[t]
    return groups


def main(argv):
    if len(argv) < 5:
        print(__doc__, file=sys.stderr)
        return 2
    timings, shard, count, tests = argv[1], int(argv[2]), int(argv[3]), argv[4:]
    if count < 1 or not 1 <= shard <= count:
        print(f"test-shard: bad shard {shard} of {count}", file=sys.stderr)
        return 2
    groups = partition(tests, load_timings(timings), count)
    flat = [t for g in groups for t in g]
    if sorted(flat) != sorted(tests) or len(flat) != len(set(flat)):
        print("test-shard: partition does not cover every test exactly once", file=sys.stderr)
        return 1
    wanted = set(groups[shard - 1])
    for t in tests:
        if t in wanted:
            print(t)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
