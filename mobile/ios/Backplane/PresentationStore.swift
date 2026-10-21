import Foundation

// Choices only. Separate identity-bound storage never opens the type-keyed
// StateStore or stores view authority, drafts, commands or a global cursor.
final class PresentationStore: @unchecked Sendable {
    private let file: URL
    private let lock = NSLock()
    private var generation: UInt64 = 0
    init(file: URL? = nil) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.file = file ?? dir.appendingPathComponent("view-choices-v1.json")
    }
    func load(links: [String], profile: String) -> String? {
        lock.withLock {
            guard let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size]) as? Int,
                  size > 0, size <= 131072, let data = try? Data(contentsOf: file),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  root["version"] as? Int == 1,
                  let identity = ScreenCache.identity(links, profile: profile), root["identity"] as? String == identity,
                  let blob = root["presentation"] as? [String: Any],
                  let encoded = try? JSONSerialization.data(withJSONObject: blob), encoded.count <= 65536 else { return nil }
            return String(data: encoded, encoding: .utf8)
        }
    }
    func save(_ text: String, links: [String], profile: String, generation: UInt64) {
        guard text.utf8.count <= 65536, let identity = ScreenCache.identity(links, profile: profile),
              let blob = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              blob["version"] as? Int == 1,
              let data = try? JSONSerialization.data(withJSONObject: ["version": 1, "identity": identity, "presentation": blob]),
              data.count <= 131072 else { return }
        lock.withLock {
            guard generation > self.generation else { return }
            #if os(iOS)
            let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            #else
            let options: Data.WritingOptions = .atomic
            #endif
            if (try? data.write(to: file, options: options)) != nil { self.generation = generation }
        }
    }
    func clear(through generation: UInt64) {
        lock.withLock {
            self.generation = max(self.generation, generation)
            try? FileManager.default.removeItem(at: file)
        }
    }
}
