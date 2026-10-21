import SwiftUI

struct PartialMessageFooter: View {
    let model: AppModel
    let hub, thread, entry: String
    let partial: MessagePartial
    var live = false
    var selected = true
    @Environment(\.backplaneLanguage) private var lang
    var body: some View {
        if partial.incomplete {
            HStack {
                Text(lang == "ja" ? "メッセージの一部" : "Partial message").foregroundStyle(.secondary)
                if partial.hasMore {
                    Button(lang == "ja" ? "続きを読む" : "More") {
                        model.moreMessage(hub: hub, thread: thread, entry: entry, partial: partial, live: live)
                    }
                    .disabled(!selected || !model.contentReady || !partial.canRequest)
                    .accessibilityIdentifier("thread.message.more." + entry)
                }
            }.font(.caption)
        }
    }
}
