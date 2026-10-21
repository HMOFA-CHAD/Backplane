import Foundation

// Display metadata only. The hub owns the full body and opaque continuation.
struct MessagePartial: Decodable, Equatable, Sendable {
    let version, cursor: String
    let hasMore, complete: Bool
    let id: String?
    var incomplete: Bool { !complete || hasMore }
    var canRequest: Bool { !complete && hasMore && !version.isEmpty && !cursor.isEmpty && cursor.utf8.count <= 1024 }
}
