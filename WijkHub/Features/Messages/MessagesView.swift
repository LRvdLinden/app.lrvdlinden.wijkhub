import SwiftUI
import Supabase

/// Tabblad Berichten: alle 1-op-1 gesprekken.
struct ConversationsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var items: [ConversationSummary] = []
    @State private var loading = false
    @State private var failed = false

    var body: some View {
        List(items) { c in
            NavigationLink(value: ChatTarget(conversationId: c.id, partnerId: c.partnerId, partnerName: c.partnerName,
                                             partnerAvatar: c.partnerAvatar, contextTitle: c.contextTitle)) {
                HStack(spacing: 12) {
                    Avatar(path: c.partnerAvatar, name: c.partnerName, size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(c.partnerName).font(.app(.headline)).lineLimit(1)
                            Spacer()
                            Text(c.lastMessageAt.formatted(.relative(presentation: .named)))
                                .font(.app(.caption)).foregroundStyle(.secondary)
                        }
                        if let context = c.contextTitle {
                            Label(context, systemImage: c.listingId != nil ? "tag" : "hand.raised")
                                .font(.app(.caption, .medium))
                                .foregroundStyle(Theme.accent)
                                .lineLimit(1)
                        }
                        HStack {
                            Text(preview(c))
                                .font(.app(.subheadline))
                                .foregroundStyle(c.unread > 0 ? .primary : .secondary)
                                .fontWeight(c.unread > 0 ? .semibold : .regular)
                                .lineLimit(2)
                            Spacer()
                            if c.unread > 0 {
                                Text(verbatim: "\(c.unread)")
                                    .font(.app(.caption, .bold))
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Theme.accent, in: Capsule())
                                    .foregroundStyle(Theme.onAccent)
                                    .accessibilityLabel(Text("\(c.unread) unread"))
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.plain)
        .overlay {
            if items.isEmpty {
                if loading {
                    ProgressView()
                } else if failed {
                    ContentUnavailableView {
                        Label("Could not load messages", systemImage: "wifi.exclamationmark")
                    } actions: {
                        Button("Try again") { Task { await load() } }
                    }
                } else {
                    ContentUnavailableView("No conversations yet", systemImage: "bubble.left.and.text.bubble.right",
                                           description: Text("Send a neighbour a message from an ad, a help request or their profile."))
                }
            }
        }
        .navigationTitle("Messages")
        .refreshable { await load() }
        .task(id: model.feedVersion) { await load() }
        .task {
            // Lijst bijwerken zolang dit scherm open is
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if scenePhase == .active { await load() }
            }
        }
    }

    private func preview(_ c: ConversationSummary) -> String {
        let body = c.lastBody ?? ""
        return c.lastSender == model.userId ? String(localized: "You: \(body)") : body
    }

    private func load() async {
        loading = true; failed = false
        defer { loading = false }
        do {
            items = try await Backend.conversations()
            model.unreadMessages = items.reduce(0) { $0 + $1.unread }
        } catch is CancellationError {
        } catch {
            failed = true
        }
    }
}

struct ChatView: View {
    let target: ChatTarget

    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var sentTick = 0
    @FocusState private var focused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    if let context = target.contextTitle {
                        Label(context, systemImage: "tag")
                            .font(.app(.caption, .medium))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Theme.tint, in: Capsule())
                            .foregroundStyle(Theme.accent)
                            .padding(.bottom, 8)
                    }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        if showsDay(at: index) {
                            Text(message.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 6)
                        }
                        Bubble(message: message, mine: message.senderId == model.userId)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.last?.id) { _, id in
                if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { inputBar }
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavigationLink(value: Route.profile(target.partnerId)) {
                    HStack(spacing: 8) {
                        Avatar(path: target.partnerAvatar, name: target.partnerName, size: 30)
                        Text(target.partnerName).font(.app(.headline)).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: sentTick)
        .task { await load() }
        .task { await listen() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .focused($focused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.line))
            Button { Task { await send() } } label: {
                Image(systemName: "arrow.up")
                    .font(.app(.headline))
                    .frame(width: 40, height: 40)
                    .background(Theme.accent, in: Circle())
                    .foregroundStyle(Theme.onAccent)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            .accessibilityLabel(Text("Send"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func showsDay(at index: Int) -> Bool {
        guard index > 0 else { return true }
        return !Calendar.current.isDate(messages[index].createdAt, inSameDayAs: messages[index - 1].createdAt)
    }

    private func load() async {
        if let fresh = try? await Backend.messages(conversation: target.conversationId) {
            messages = fresh
            await Backend.markRead(target.conversationId)
            await model.refreshUnread()
        }
    }

    /// Live: bij elk nieuw bericht in dit gesprek opnieuw laden. Valt terug op elke 10 s als realtime niet werkt.
    private func listen() async {
        let channel = Backend.client.channel("chat-\(target.conversationId.uuidString.lowercased())")
        let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: "messages",
                                             filter: "conversation_id=eq.\(target.conversationId.uuidString.lowercased())")
        try? await channel.subscribeWithError()
        let poll = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await load()
            }
        }
        for await _ in inserts {
            await load()
        }
        poll.cancel()
        await Backend.client.removeChannel(channel)
    }

    private func send() async {
        guard let me = model.userId else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            try await Backend.sendMessage(conversation: target.conversationId, sender: me, body: text)
            draft = ""
            sentTick += 1
            await load()
        } catch {
            model.lastError = String(localized: "Your message could not be sent.")
        }
    }
}

private struct Bubble: View {
    let message: ChatMessage
    let mine: Bool

    var body: some View {
        HStack {
            if mine { Spacer(minLength: 48) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                Text(message.body)
                    .textSelection(.enabled)
                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.app(.caption2))
                    .opacity(0.7)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(mine ? Theme.accent : Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(mine ? Theme.onAccent : Color.primary)
            if !mine { Spacer(minLength: 48) }
        }
    }
}
