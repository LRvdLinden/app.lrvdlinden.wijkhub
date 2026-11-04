import SwiftUI
import PhotosUI

/// Profiel van jezelf of van een buur, met de berichten van die persoon.
struct ProfileView: View {
    let userId: UUID

    @Environment(AppModel.self) private var model
    @State private var profile: Profile?
    @State private var phone: String?
    @State private var posts: [Post] = []
    @State private var editing = false
    @State private var reportTarget: ReportTarget?
    @State private var confirmBlock = false
    @State private var openPost: Post?
    @State private var listings: [Listing] = []
    @State private var chat: ChatTarget?
    @State private var startingChat = false

    private var isMe: Bool { userId == model.userId }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if !isMe, profile != nil {
                    Button { Task { await startChat() } } label: {
                        ProgressLabel(title: "Send a message", busy: startingChat)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(startingChat)
                }
                if !listings.isEmpty {
                    Text("In the market")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(listings) { l in
                                NavigationLink(value: l) { ListingCard(listing: l).frame(width: 150) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if !posts.isEmpty {
                    Text("Messages")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
                ForEach($posts) { $post in
                    PostRow(post: $post, onOpen: { openPost = post },
                            onRemoved: { posts.removeAll { $0.id == post.id } })
                        .onTapGesture { openPost = post }
                }
            }
            .padding(16)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(isMe ? String(localized: "My profile") : (profile?.displayName ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isMe {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { editing = true }
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(Text("Settings"))
                }
            } else if profile != nil {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Report profile", systemImage: "flag") {
                            if let wijk = model.wijk?.id { reportTarget = .profile(userId, wijk: wijk) }
                        }
                        Button("Block", systemImage: "hand.raised", role: .destructive) { confirmBlock = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(Text("More actions"))
                }
            }
        }
        .sheet(isPresented: $editing, onDismiss: { Task { await load() } }) {
            EditProfileView()
        }
        .sheet(item: $reportTarget) { ReportSheet(target: $0) }
        .confirmationDialog("Block this neighbour?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) { Task { await block() } }
        } message: {
            Text("You will no longer see messages and comments from this neighbour.")
        }
        .navigationDestination(item: $openPost) { PostDetailView(postId: $0.id, initial: $0) }
        .navigationDestination(item: $chat) { ChatView(target: $0) }
        .refreshable { await load() }
        .task(id: model.feedVersion) { await load() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Avatar(path: profile?.avatarPath, name: profile?.displayName ?? "", size: 96)
            Text(profile?.displayName ?? " ")
                .font(.title2.bold())
            if let profile, !profile.straat.isEmpty || model.wijk != nil {
                Label {
                    Text([profile.straat, model.wijk?.naam].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            if let bio = profile?.bio, !bio.isEmpty {
                Text(bio)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            if let phone, !phone.isEmpty, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                HStack(spacing: 12) {
                    Link(destination: url) {
                        Label(phone, systemImage: "phone")
                    }
                    if !isMe, let wa = URL(string: "https://wa.me/\(Self.whatsAppNumber(phone))") {
                        Link(destination: wa) {
                            Label("WhatsApp", systemImage: "message")
                        }
                    }
                }
                .font(.subheadline.weight(.medium))
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.line))
    }

    /// 06-12345678 → 31612345678
    static func whatsAppNumber(_ phone: String) -> String {
        var digits = phone.filter(\.isNumber)
        if phone.hasPrefix("+") { return digits }
        if digits.hasPrefix("00") { digits.removeFirst(2); return digits }
        if digits.hasPrefix("0") { digits.removeFirst(); return "31" + digits }
        return digits
    }

    private func load() async {
        profile = try? await Backend.profile(userId)
        let contact = try? await Backend.contact(userId)
        phone = contact?.telefoon
        if let wijk = model.wijk?.id {
            posts = (try? await Backend.feed(wijk: wijk, author: userId)) ?? posts
            listings = (try? await Backend.listings(wijk: wijk, author: userId, includeSold: isMe)) ?? listings
        }
    }

    private func startChat() async {
        startingChat = true
        defer { startingChat = false }
        do {
            let id = try await Backend.startConversation(with: userId)
            chat = ChatTarget(conversationId: id, partnerId: userId, partnerName: profile?.displayName ?? "",
                              partnerAvatar: profile?.avatarPath, contextTitle: nil)
        } catch {
            model.lastError = String(localized: "Could not start a conversation.")
        }
    }

    private func block() async {
        guard let me = model.userId else { return }
        do {
            try await Backend.block(userId, by: me)
            model.feedVersion += 1
        } catch {
            model.lastError = error.localizedDescription
        }
    }
}

struct EditProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var bio = ""
    @State private var straat = ""
    @State private var phone = ""
    @State private var phoneVisible = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var busy = false
    @State private var saved = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            if let photoData, let ui = UIImage(data: photoData) {
                                Image(uiImage: ui).resizable().scaledToFill()
                                    .frame(width: 88, height: 88).clipShape(Circle())
                            } else {
                                Avatar(path: model.profile?.avatarPath, name: name, size: 88)
                            }
                        }
                        .accessibilityLabel(Text("Choose profile photo"))
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Name") {
                    TextField("First and last name", text: $name).textContentType(.name)
                }
                Section("About you") {
                    TextField("A few words about yourself", text: $bio, axis: .vertical).lineLimit(2...5)
                    TextField("Street (optional)", text: $straat).textContentType(.streetAddressLine1)
                }
                Section {
                    TextField("Mobile number (optional)", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    Toggle("Show my number to neighbours", isOn: $phoneVisible)
                        .disabled(phone.trimmingCharacters(in: .whitespaces).isEmpty)
                        .tint(Theme.accent)
                } header: {
                    Text("Contact")
                } footer: {
                    Text("Only neighbours in your own neighbourhood can see your number, and only if you switch this on.")
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else {
                        Button("Save") { Task { await save() } }
                            .disabled(name.trimmingCharacters(in: .whitespaces).count < 2)
                    }
                }
            }
            .sensoryFeedback(.success, trigger: saved)
        }
        .onAppear {
            name = model.profile?.displayName ?? ""
            bio = model.profile?.bio ?? ""
            straat = model.profile?.straat ?? ""
            phone = model.contact?.telefoon ?? ""
            phoneVisible = model.contact?.telefoonZichtbaar ?? false
        }
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    photoData = ImageTools.jpeg(from: data, maxSide: 600)
                }
            }
        }
    }

    private func save() async {
        guard let me = model.userId else { return }
        busy = true
        defer { busy = false }
        do {
            var avatar = model.profile?.avatarPath
            if let photoData { avatar = try await Backend.uploadImage(photoData, owner: me) }
            try await Backend.updateProfile(me, name: name.trimmingCharacters(in: .whitespaces),
                                            bio: bio.trimmingCharacters(in: .whitespacesAndNewlines),
                                            straat: straat.trimmingCharacters(in: .whitespaces), avatarPath: avatar)
            let p = phone.trimmingCharacters(in: .whitespaces)
            try await Backend.updateContact(me, phone: p, visible: !p.isEmpty && phoneVisible)
            saved += 1
            await model.reload()
            dismiss()
        } catch {
            model.lastError = error.localizedDescription
        }
    }
}
