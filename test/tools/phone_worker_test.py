#!/usr/bin/env python3
"""Extract the production Swift worker and test its two FIFO lanes on a Mac.

python3 test/tools/phone_worker_test.py build/snappy/worker.swift
swiftc build/snappy/worker.swift -o build/snappy/worker && build/snappy/worker
No app, simulator, hub or persisted client state is used.
"""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[2]
source = (root / "mobile/ios/Backplane/Engine.swift").read_text()
worker = source[source.index("private final class Worker:"):source.index("// The Bend client")]
fixture = '''
final class Recording: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func add(_ value: String) { lock.withLock { values.append(value) } }
    var all: [String] { lock.withLock { values } }
}
private let worker = Worker()
let started = DispatchSemaphore(value: 0)
let release = DispatchSemaphore(value: 0)
let finished = DispatchSemaphore(value: 0)
let recording = Recording()
worker.async(person: false) { started.signal(); release.wait() }
precondition(started.wait(timeout: .now() + 5) == .success)
worker.async(person: false) { recording.add("recv1") }
worker.async(person: false) { recording.add("recv2") }
worker.async(person: true) { recording.add("act1") }
worker.async(person: true) { recording.add("quiet2") }
worker.async(person: false) { recording.add("tick3"); finished.signal() }
precondition(worker.personWaiting, "the person lane must be visible during background work")
release.signal()
precondition(finished.wait(timeout: .now() + 5) == .success)
precondition(recording.all == ["act1", "quiet2", "recv1", "recv2", "tick3"], "FIFO in each lane, person first")
precondition(!worker.personWaiting)
print("PASS: production Swift worker: act1 quiet2 recv1 recv2 tick3; personWaiting clears")
'''
Path(sys.argv[1]).write_text("import Foundation\n" + worker + fixture)
