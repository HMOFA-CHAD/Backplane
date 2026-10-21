import Foundation

// The hub and raw conversation ID occupy separate JSON fields. A mail ID
// can contain |; it must never pass through the generic host|value splitter.
enum MailroomAction {
    // Same action boundary as Session.mail.action: never defer these until
    // a cached presentation becomes canonical.
    static func isCommand(_ action: String, _ value: String) -> Bool {
        action.hasPrefix("mail-") || action == "mailroom-action" ||
        (action == "bot-tab" && value == "mail") ||
        (action == "bfield" && value.hasPrefix("mrreply\u{1f}"))
    }

    static func waiting(live: Bool, contentReady: Bool, loading: Bool) -> Bool {
        !live || !contentReady || loading
    }

    static func request(_ mailroom: MailroomModel, _ action: String, _ value: String = "",
                        draft: String? = nil, recipient: String? = nil) -> String {
        var fields = ["hub": mailroom.hub, "owner": mailroom.owner,
                      "conversation": mailroom.body?.id ?? "", "action": action, "value": value]
        if let draft { fields["draft"] = draft }
        if let recipient { fields["recipient"] = recipient }
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

struct MailroomReturnContext {
    let hub, owner: String
}

struct MailroomListWindow: Hashable {
    let filter, query: String
    let first: Int
}

struct MailroomPositionKey: Hashable {
    let hub, origin, owner, conversation: String
    var list: MailroomListWindow? = nil
}

// A validated current-connection history marker can arrive without a screen
// when Engine drops a superseded frame. Keep it until the next accepted frame.
struct PresentationReadiness {
    private var epochs: [String: UInt64] = [:]
    private var requested: [String: UInt64] = [:]

    mutating func observe(hub: String, epoch: UInt64, phase: String) {
        if phase == "presented" || phase == "live" { epochs[hub] = epoch }
        else if phase == "recent" || phase == "failed" { retire(hub) }
    }

    mutating func retire(_ hub: String) { epochs[hub] = nil; requested[hub] = nil }
    mutating func clear() { epochs.removeAll(); requested.removeAll() }

    // Request at most one current snapshot per validated hub/epoch. A
    // flush can reach MainActor before its earlier metadata callback.
    mutating func requestFrame(current: (String) -> UInt64?) -> Bool {
        for (hub, epoch) in epochs where current(hub) == epoch && requested[hub] != epoch {
            requested[hub] = epoch
            return true
        }
        return false
    }

    func accepts(current: (String) -> UInt64?) -> Bool {
        epochs.contains { hub, epoch in current(hub) == epoch }
    }
}
