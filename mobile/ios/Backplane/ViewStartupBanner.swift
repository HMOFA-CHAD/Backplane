import SwiftUI

struct ViewStartupBanner: View {
    let model: AppModel
    private var key: String? {
        if let hub = model.screen?.hub, !hub.isEmpty {
            return model.startup[hub] == .compatibilityRequired ? hub : nil
        }
        return model.startup.keys.sorted().first { model.startup[$0] == .compatibilityRequired }
    }
    var body: some View {
        if let key {
            VStack(alignment: .leading, spacing: 4) {
                Text("Fast loading unavailable · " + key).font(.caption)
                HStack {
                    Button("Retry") { model.retryView(key) }
                    Spacer()
                    Button("Download history for this session") { model.retryView(key, compatibility: true) }
                }.font(.caption)
            }.padding(10).background(.bar)
        }
    }
}
