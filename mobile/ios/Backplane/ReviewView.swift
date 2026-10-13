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
                    if let c = page.checks { ChecksBoxes(model: model, checks: c).padding([.horizontal, .top]) }
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

// The Checks page's gate and checklist: a red "Fails: ..." or a green
// "Passes", then the boxes as toggles under their headings. A tap sends
// "rv-tick" index; the hub writes .backplane/checklist.md and answers the
// boxes, so a toggle shows what the hub says.
struct ChecksBoxes: View {
    let model: AppModel
    let checks: ReviewChecks

    private var groups: [(String, [ReviewTask])] {
        var out: [(String, [ReviewTask])] = []
        for t in checks.tasks {
            if let i = out.firstIndex(where: { $0.0 == t.group }) { out[i].1.append(t) } else { out.append((t.group, [t])) }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(checks.gate.isEmpty ? "Passes" : "Fails: " + checks.gate,
                  systemImage: checks.gate.isEmpty ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(checks.gate.isEmpty ? Color.green : Color.red)
                .accessibilityIdentifier("checks-gate")
            ForEach(groups, id: \.0) { g in
                VStack(alignment: .leading, spacing: 0) {
                    if !g.0.isEmpty { Text(g.0).font(.headline).padding(.vertical, 6) }
                    ForEach(g.1, id: \.index) { t in
                        Toggle(isOn: Binding(get: { t.done }, set: { _ in model.act("rv-tick", String(t.index)) })) {
                            Text(t.text).font(.body)
                        }
                        .toggleStyle(CheckBoxStyle())
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// a square box and its words, the whole row the tap's size
struct CheckBoxStyle: ToggleStyle {
    func makeBody(configuration c: Configuration) -> some View {
        Button { c.isOn.toggle() } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: c.isOn ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundStyle(c.isOn ? Color.accentColor : .secondary)
                c.label.multilineTextAlignment(.leading).foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// The note for a new comment, as a bottom sheet small enough to leave the
// board (and the place) in view. The text goes to Bend as the field
// "rcnote" while it is typed; Send posts it.
struct NoteSheet: View {
    let model: AppModel
    let at: String
    @State private var text = ""
    @FocusState private var focus: Bool

    private var place: String {
        let p = at.split(separator: "\t", omittingEmptySubsequences: false)
        guard p.count >= 2, let x = Double(p[0]), let y = Double(p[1]) else { return "" }
        return String(format: "at %.2f, %.2f mm", x, y)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Comment").font(.headline)
                Text(place).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { model.act("rv-note-shut", "") }
            }
            TextField("Write a note", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($focus)
                .onChange(of: text) { _, t in model.field("rcnote", t) }
                .accessibilityIdentifier("note-field")
            Button {
                model.act("rv-note-send", "")
            } label: { Text("Send").frame(maxWidth: .infinity, minHeight: 32) }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("note-send")
        }
        .padding()
        .presentationDetents([.height(230)])
        .presentationBackgroundInteraction(.enabled)
        .onAppear {
            focus = true
            #if DEBUG
            if let t = ProcessInfo.processInfo.environment["BACKPLANE_NOTE"] { text = t }
            #endif
        }
    }
}

// The open comment: its words, who and where, the replies, a reply field,
// Resolve or Reopen, Close. A sheet of two heights: the pin stays in view
// at the lower one.
struct CommentSheet: View {
    let model: AppModel
    let open: ReviewOpen
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(open.by).font(.headline)
                if open.resolved { Text("Resolved").font(.caption).foregroundStyle(.green) }
                Spacer()
                Button { model.act("rv-pin", "") } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                    .accessibilityLabel("Close")
            }
            if !open.place.isEmpty { Text(open.place).font(.caption).foregroundStyle(.secondary) }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(open.text).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Array(open.replies.enumerated()), id: \.offset) { _, r in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.by).font(.caption).foregroundStyle(.secondary)
                            Text(r.text)
                        }
                        .padding(.leading, 12)
                    }
                }
            }
            HStack {
                TextField("Reply", text: $text, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: text) { _, t in model.field("rcreply", t) }
                    .accessibilityIdentifier("reply-field")
                Button("Reply") {
                    model.act("rv-reply-send", "")
                    text = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("reply-send")
            }
            Button(open.resolved ? "Reopen" : "Resolve") { model.act(open.resolved ? "rv-reopen" : "rv-resolve", open.id) }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .accessibilityIdentifier("resolve")
        }
        .padding()
        #if DEBUG
        .onAppear { if let t = ProcessInfo.processInfo.environment["BACKPLANE_REPLY"] { text = t } }
        #endif
        .presentationDetents([.height(320), .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .height(320)))
    }
}
