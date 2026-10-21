// A declined gesture never consumes its page. Readiness changes alone do not
// request data: only the scroll controller's existing real-drag gate calls here.
struct EarlierPageGate {
    private var enabled = false
    private var requested: Int?

    mutating func configure(enabled: Bool) {
        self.enabled = enabled
        if !enabled { requested = nil }
    }

    @discardableResult mutating func request(_ earlier: Int, perform: () -> Bool) -> Bool {
        guard enabled, earlier > 0, requested != earlier, perform() else { return false }
        requested = earlier
        return true
    }
}
