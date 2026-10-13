import SwiftUI

// The viewer's Review tab (client.bend's Rp, mobile/view.bend's Rv.json): a
// chip per page, the page's title and the report as Markdown (the apps'
// own MarkdownView; its tables scroll sideways), or what to say while
// there is none. Refresh sits at the bottom, under the thumb.
struct ReviewScreen: View {
    let model: AppModel
    let viewer: Viewer
    let page: ReviewPage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewerChoices(model: model, viewer: viewer)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(page.tabs, id: \.page) { t in
                        Button(t.label) { model.act("rv-page", t.page) }
                            .buttonStyle(.bordered)
                            .tint(t.on ? Color.accentColor : .secondary)
                    }
                }
                .padding(.horizontal)
            }
            Text(page.title).font(.headline).lineLimit(2)
                .padding(.horizontal).padding(.vertical, 6)
            Divider()
            if let blocks = page.blocks, !blocks.isEmpty, !page.busy {
                ScrollView {
                    MarkdownView(blocks: blocks).padding()
                }
            } else {
                VStack {
                    if page.busy { ProgressView() }
                    Text(page.note).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            Button { model.act("rv-run", "") } label: {
                Label("Refresh", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(page.busy)
            .padding()
        }
    }
}
