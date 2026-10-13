#!/usr/bin/env python3
"""Generate a Mac JSC test of the production iOS engine (no simulator).

python3 test/tools/phone_engine_test.py ENGINE.swift OUT.swift
xcrun swiftc -parse-as-library OUT.swift -o OUT && OUT
The tiny bridge fixture models shows/owed, counts renders, and retains cmds.
"""
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
old = '''        let url = Bundle.main.url(forResource: "bridge", withExtension: "js")!
        c.evaluateScript(try! String(contentsOf: url, encoding: .utf8), withSourceURL: url)'''
fixture = '''        let hold: @convention(block) () -> Void = { Signals.started.signal(); Signals.release.wait() }
        c.setObject(hold, forKeyedSubscript: "hold" as NSString)
        c.evaluateScript("""
          let owed = false, version = 0, nav = '', renders = 0;
          const out = (quiet) => { if (!quiet) { owed = false; renders++; }
            return JSON.stringify({screen: quiet ? null : {nav, version}, cmds: ['kept']}); };
          globalThis.Backplane = {
            start: () => out(false),
            save: () => { hold(); return 'kept'; },
            cat: () => String(renders),
            act: (a, v) => { nav = v; return out(false); },
            recv: (k, data, quiet, owe) => { version++; const shows = data !== 'off';
              if (owe || (quiet && shows)) owed = true;
              return out(quiet || !(shows || owed)); },
            flush: (owe) => { if (owe) owed = true; return out(!owed); }
          };
        """)'''
assert old in source
source = source.replace(old, fixture)
# Observe enqueue completion to make the backlog test deterministic. The
# worker ordering and every engine method remain the production code.
source = source.replace('''        cond.signal()
        cond.unlock()''','''        cond.signal()
        cond.unlock()
        Signals.enqueued.signal()''',1)
stubs = '''
struct TestScreen: Decodable, Sendable { let nav: String; let version: Int }
struct Out: Decodable, Sendable {
    let screen: TestScreen?
    let cmds: [String]
    static func decode(_ text: String, screen: Bool) -> Out? {
        guard let o = try? JSONDecoder().decode(Out.self, from: Data(text.utf8)) else { return nil }
        return Out(screen: screen ? o.screen : nil, cmds: o.cmds)
    }
}
final class Results: @unchecked Sendable {
    let got = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var frames: [TestScreen] = []
    func accept(_ o: Out?) { if let s = o?.screen { lock.withLock { frames.append(s) }; got.signal() } }
    var last: TestScreen? { lock.withLock { frames.last } }
}
enum Signals {
    static let started = DispatchSemaphore(value: 0)
    static let release = DispatchSemaphore(value: 0)
    static let enqueued = DispatchSemaphore(value: 0)
    static func queued() { precondition(enqueued.wait(timeout: .now() + 2) == .success) }
}
@main struct Test {
    static func main() async {
        let e = Engine()
        let results = Results()
        e.onFlush = { results.accept($0) }
        _ = await e.start("test", "{}")
        Signals.queued()
        let block = Task.detached { await e.save() }
        precondition(Signals.started.wait(timeout: .now() + 2) == .success)
        Signals.queued()
        let r1 = Task.detached { await e.recv("fixture", "visible") }; Signals.queued()
        let r2 = Task.detached { await e.recv("fixture", "visible") }; Signals.queued()
        let person = Task.detached { await e.act("select", "bot-thread") }; Signals.queued()
        Signals.release.signal()
        let p = await person.value
        precondition(p?.screen?.nav == "bot-thread", "queued background calls must not drop the person's screen")
        precondition(await block.value == "kept")
        let a = await r1.value, b = await r2.value
        precondition(a?.screen == nil && b?.screen == nil, "streaming window coalesces the backlog")
        precondition(a?.cmds == ["kept"] && b?.cmds == ["kept"], "quiet frames retain commands")
        precondition(results.got.wait(timeout: .now() + 2) == .success, "last visible frame must flush without another recv")
        precondition(results.last?.version == 2 && results.last?.nav == "bot-thread")
        print("PASS: person screen survives queued recv; two quiet frames retain cmds; final version 2 flushes")
        let rendered = await e.cat("stats")
        _ = await e.recv("fixture", "off")
        // Wait for the inert flush via a background barrier, with a bounded
        // delay in this regression only (not in the app).
        try? await Task.sleep(nanoseconds: 350_000_000)
        let after = await e.cat("stats")
        precondition(rendered == after, "off-screen traffic must not render a screen")
        print("PASS: off-screen traffic and its timer build no screen")
    }
}
'''
# Awaiting in precondition's autoclosure is forbidden in Swift.
stubs = stubs.replace('precondition(await block.value == "kept")','let saved = await block.value\n        precondition(saved == "kept")')
Path(sys.argv[2]).write_text(source + stubs)
