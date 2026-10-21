// Compile with the actual production EarlierPageGate.swift in the next coherent
// native workflow. Helper proof only; root actual gestures remain the UI gate.
@main struct EarlierPageGateCases {
    static func main() {
        var gate = EarlierPageGate(), calls = 0
        func accepted() -> Bool { calls += 1; return true }
        gate.configure(enabled: false)
        gate.beginDrag()
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
        precondition(!gate.request(24000, perform: accepted), "reply/remaining change during same drag cannot request another page")
        precondition(calls == 1, "readiness and earlier count never reset accepted gesture")
        gate.beginDrag()
        precondition(calls == 1, "new drag beginning alone does not page")
        precondition(gate.request(24000, perform: accepted), "next real drag may request one bounded page")
        for earlier in [23968, 23936, 23904] {
            gate.configure(enabled: false)
            gate.configure(enabled: true)
            precondition(!gate.request(earlier, perform: accepted), "same drag/deceleration cannot cascade across replies")
        }
        precondition(!gate.request(0, perform: accepted))
        precondition(calls == 2)
        print("PASS production EarlierPageGate: declined not consumed, exactly one accepted page per real drag, reply/readiness/count changes cannot cascade, next drag permits next page")
    }
}
