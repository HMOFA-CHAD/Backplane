import SwiftUI

private struct MailroomIdentity: Hashable {
    let hub, origin, owner, conversation: String
}

struct MailroomScreen: View {
    @Environment(\.backplaneLanguage) private var lang
    let model: AppModel
    let mailroom: MailroomModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(mailroom.machine).font(.caption.weight(.semibold))
                if !mailroom.online {
                    Text(NativeMessages.native_mailroom_machine_offline(lang)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal).padding(.vertical, 6)
            Divider()
            if let body = mailroom.body {
                MailroomConversation(model: model, mailroom: mailroom, conversation: body)
                    .id(MailroomIdentity(hub: mailroom.hub, origin: mailroom.origin ?? "", owner: mailroom.owner, conversation: body.id))
            } else {
                MailroomList(model: model, mailroom: mailroom)
                    .id(MailroomIdentity(hub: mailroom.hub, origin: mailroom.origin ?? "", owner: mailroom.owner, conversation: ""))
            }
        }
        .accessibilityIdentifier("mailroom.screen")
    }
}

private struct MailroomList: View {
    @Environment(\.backplaneLanguage) private var lang
    let model: AppModel
    let mailroom: MailroomModel
    private var position: TimelinePosition { model.mailroomPosition(mailroom, conversation: "") }
    @State private var query = ""

    private func filter(_ value: String, _ label: String) -> some View {
        Button(label) { model.mailroom(mailroom, "mail-filter", value) }
            .fontWeight(mailroom.status == value ? .semibold : .regular)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField(NativeMessages.common_search(lang), text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { model.mailroom(mailroom, "mail-search", query) }
                    .accessibilityIdentifier("mailroom.search")
                Button { model.mailroom(mailroom, "mail-search", query) } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel(NativeMessages.common_search(lang))
            }.padding(.horizontal)
            HStack(spacing: 16) {
                filter("", NativeMessages.viewer_layers_all(lang))
                filter("unread", NativeMessages.native_plane_unread(lang))
                filter("act", NativeMessages.native_mailroom_act(lang))
                filter("fyi", NativeMessages.native_mailroom_fyi(lang))
                Spacer(minLength: 0)
                if mailroom.loading { ProgressView().controlSize(.small) }
            }.font(.caption).padding(.horizontal)
            TimelineScroll(position: position, ids: mailroom.rows.map(\.id), earlier: 0, loadEarlier: { false }, startsAtLatest: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if mailroom.rows.isEmpty {
                        Text(mailroom.loading ? NativeMessages.viewer_loading(lang) : NativeMessages.native_bot_messages_empty(lang))
                            .foregroundStyle(.secondary).padding()
                    }
                    ForEach(mailroom.rows) { row in
                        Button { model.mailroom(mailroom, "mail-open", row.id) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    if row.unread { Circle().fill(Color.accentColor).frame(width: 6, height: 6) }
                                    Text(row.subject).fontWeight(row.unread ? .semibold : .regular)
                                    Spacer(minLength: 4)
                                    if row.live { ProgressView().controlSize(.mini) }
                                }
                                Text(row.who).font(.caption).foregroundStyle(.secondary)
                                Text(row.head).font(.subheadline).lineLimit(2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(TimelineMarker(id: row.id))
                        .accessibilityIdentifier("mailroom.row." + row.id)
                        Divider()
                    }
                }
            }
            .id(ObjectIdentifier(position))
            HStack {
                Button(NativeMessages.common_earlier(lang)) { model.mailroom(mailroom, "mail-window", String(max(0, mailroom.first - 50))) }
                    .disabled(mailroom.first == 0)
                Spacer()
                Text(NativeMessages.native_mailroom_page(lang, String(mailroom.total == 0 ? 0 : mailroom.first + 1), String(mailroom.first + mailroom.rows.count), String(mailroom.total)))
                    .font(.caption).monospacedDigit()
                Spacer()
                Button(NativeMessages.native_mailroom_later(lang)) { model.mailroom(mailroom, "mail-window", String(mailroom.first + 50)) }
                    .disabled(mailroom.first + mailroom.rows.count >= mailroom.total)
            }.font(.caption).padding(.horizontal).padding(.bottom, 8)
        }
        .padding(.top, 8)
        .onAppear { query = mailroom.query }
        .onChange(of: mailroom.query) { old, new in
            if query == old { query = new }
        }
    }
}

private struct MailroomConversation: View {
    @Environment(\.backplaneLanguage) private var lang
    let model: AppModel
    let mailroom: MailroomModel
    let conversation: MailroomBody
    private var position: TimelinePosition { model.mailroomPosition(mailroom, conversation: conversation.id) }
    @State private var draft = ""
    @State private var recipient = ""

    private var status: String {
        switch conversation.sendState {
        case "pending": NativeMessages.native_thread_sending(lang)
        case "accepted": NativeMessages.native_mailroom_accepted_unconfirmed(lang)
        case "unknown": NativeMessages.native_mailroom_outcome_unknown(lang)
        case "failed": NativeMessages.native_thread_send_failed(lang)
        default: ""
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { model.mailroom(mailroom, "mail-close") } label: {
                    Label(NativeMessages.tour_back(lang), systemImage: "chevron.left")
                }
                Spacer()
                Text(conversation.subject).font(.headline).lineLimit(2)
                Spacer()
                if conversation.loading { ProgressView().controlSize(.small) }
            }.padding(.horizontal).padding(.vertical, 8)
            TimelineScroll(position: position, ids: conversation.messages.map(\.id), earlier: 0, loadEarlier: { false }) {
                VStack(alignment: .leading, spacing: 16) {
                    if !conversation.previousAnchor.isEmpty {
                        Button(NativeMessages.common_earlier(lang)) { model.mailroom(mailroom, "mail-body-window", conversation.previousAnchor) }
                    } else if conversation.remoteEarlier {
                        Button(NativeMessages.common_earlier(lang)) { model.mailroom(mailroom, "mail-more") }
                            .disabled(conversation.loading || !mailroom.online)
                    }
                    ForEach(conversation.messages) { message in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(message.who).font(.caption.weight(.semibold))
                                Spacer()
                                if !message.sourceURI.isEmpty {
                                    Button { model.openMailroomSource(mailroom, uri: message.sourceURI) } label: { Image(systemName: "arrow.up.right") }
                                        .accessibilityLabel(NativeMessages.native_mailroom_open_source(lang))
                                        .accessibilityIdentifier("mailroom.source." + message.id)
                                }
                            }
                            // Full body, with no character cap or line limit.
                            Text(message.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .background(TimelineMarker(id: message.id))
                        .accessibilityIdentifier("mailroom.message." + message.id)
                    }
                    if !conversation.nextAnchor.isEmpty {
                        Button(NativeMessages.native_mailroom_later(lang)) { model.mailroom(mailroom, "mail-body-window", conversation.nextAnchor) }
                    }
                }.padding()
            }
            .overlay(alignment: .bottomTrailing) {
                if !position.following || !conversation.nextAnchor.isEmpty {
                    Button(NativeMessages.native_thread_latest(lang)) {
                        if position.following { model.mailroom(mailroom, "mail-body-window", "") }
                        position.latest?()
                    }
                    .font(.caption.bold()).padding(10).background(.regularMaterial).padding(8)
                    .accessibilityIdentifier("mailroom.latest")
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Picker(NativeMessages.native_mailroom_recipient(lang), selection: $recipient) {
                    Text(NativeMessages.native_mailroom_recipient(lang)).tag("")
                    ForEach(conversation.targets, id: \.address) { target in Text(target.label).tag(target.address) }
                }.onChange(of: recipient) { _, value in model.mailroom(mailroom, "mail-to", value) }
                HStack(alignment: .bottom) {
                    TextField(NativeMessages.review_reply(lang), text: $draft, axis: .vertical)
                        .lineLimit(1...6)
                        .onChange(of: draft) { _, text in
                            model.mailroom(mailroom, "bfield", "mrreply\u{1f}" + text, quiet: true)
                        }
                        .accessibilityIdentifier("mailroom.reply")
                    Button(NativeMessages.composer_send(lang)) {
                        model.mailroom(mailroom, "mail-send", draft: draft, recipient: recipient)
                    }
                    .disabled(!mailroom.online || recipient.isEmpty || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("mailroom.send")
                }
                if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("mailroom.send-status") }
            }.padding()
        }
        .onAppear { draft = conversation.draft; recipient = conversation.to }
        .onChange(of: conversation.draft) { old, new in if draft == old { draft = new } }
        .onChange(of: conversation.windowAnchor) { _, _ in
            if !position.following { position.resetToStart(firstID: conversation.messages.first?.id) }
        }
        .onChange(of: position.following) { _, following in
            model.mailroom(mailroom, "mail-body-window", following ? "" : conversation.windowAnchor)
        }
    }
}
