// Compile with the actual production EarlierPageGate.swift in the next coherent
// native workflow. Helper proof only; root actual gestures remain the UI gate.
@main struct EarlierPageGateCases {
    static func main() {
        var gate = EarlierPageGate(), calls = 0
        func accepted() -> Bool { calls += 1; return true }
        gate.configure(enabled: false)
        precondition(!gate.request(24032, perform: accepted))
        precondition(calls == 0, "cached-unready gesture is not consumed or dispatched")
        gate.configure(enabled: true)
        precondition(calls == 0, "readiness alone never pages")
        precondition(!gate.request(24032) { false }, "declined callback does not latch")
        precondition(gate.request(24032, perform: accepted), "later real accepted gesture requests page")
        precondition(!gate.request(24032, perform: accepted), "same page has exactly one accepted dispatch")
        precondition(calls == 1)
        gate.configure(enabled: false)
        precondition(!gate.request(24032, perform: accepted))
        gate.configure(enabled: true)
        precondition(calls == 1, "reconnect/refresh never retries automatically")
        precondition(gate.request(24032, perform: accepted), "new gesture after fresh readiness may request same page")
        precondition(!gate.request(24032, perform: accepted))
        precondition(gate.request(24000, perform: accepted), "another explicit gesture can request the next bounded page")
        precondition(!gate.request(0, perform: accepted))
        precondition(calls == 3)
        print("PASS production EarlierPageGate: unready/declined not latched, ready-only inert, accepted once, retry only on another gesture")
    }
}
