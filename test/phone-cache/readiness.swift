import Foundation

func require(_ yes: @autoclosure () -> Bool, _ message: String) {
    if !yes() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
@main struct ReadinessTest {
    static func main() {
        var gate = PresentationReadiness()
        let current = ["selected": UInt64(3)]
        gate.observe(hub: "selected", epoch: 3, phase: "history")
        require(!gate.accepts { current[$0] }, "partial history never releases cached screen")
        gate.observe(hub: "other", epoch: 3, phase: "presented")
        require(!gate.accepts { current[$0] }, "unrelated hub does not release selected cache")
        gate.observe(hub: "selected", epoch: 2, phase: "presented")
        require(!gate.accepts { current[$0] }, "previous connection cannot release cache")
        gate.observe(hub: "selected", epoch: 3, phase: "presented")
        require(gate.accepts { current[$0] }, "selected current presentation releases cache")
        require(gate.requestFrame { current[$0] }, "dropped screen requests one frame")
        require(!gate.requestFrame { current[$0] }, "same marker cannot spin frame requests")
        let selectedNav = "selected|thread"
        let newerNav = "selected|newer"
        require(!gate.accepts { key in selectedNav == newerNav ? current[key] : nil }, "new selection rejects late old presentation")
        gate.retire("selected")
        require(!gate.accepts { current[$0] }, "disconnect retires marker")
        gate.observe(hub: "selected", epoch: 4, phase: "live")
        require(gate.accepts { $0 == "selected" ? 4 : nil }, "old hub canonical terminal fallback stays usable")
        gate.clear()
        require(!gate.accepts { _ in 4 }, "profile or cache change removes freshness")
        print("PASS: partial-history, other-hub, stale-epoch, presented, dropped-frame-once, stale-selection, disconnect, legacy-live, profile-clear")
    }
}
