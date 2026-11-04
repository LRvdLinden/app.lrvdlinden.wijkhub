import SwiftUI
import PhotosUI

struct ComposePostView: View {
    var preselected: BuurtGroup?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var groupId: UUID?
    @State private var text = ""
    @State private var items: [PhotosPickerItem] = []
    @State private var images: [Data] = []
    @State private var busy = false
    @State private var error: String?
    @State private var posted = 0
    @FocusState private var focused: Bool

    private var group: BuurtGroup? { model.groups.first { $0.id == groupId } }
    private var canPost: Bool {
        group != nil && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Group", selection: $groupId) {
                        ForEach(model.groups) { g in
                            Label(g.naam, systemImage: g.soort.symbol).tag(Optional(g.id))
                        }
                    }
                }
                if group?.soort == .preventie {
                    Section { EmergencyBanner().listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
                }
                Section {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .lineLimit(5...14)
                        .focused($focused)
                }
                Section {
                    if !images.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(images.indices, id: \.self) { i in
                                    if let ui = UIImage(data: images[i]) {
                                        Image(uiImage: ui).resizable().scaledToFill()
                                            .frame(width: 88, height: 88)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                            .overlay(alignment: .topTrailing) {
                                                Button { remove(at: i) } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .symbolRenderingMode(.palette)
                                                        .foregroundStyle(.white, .black.opacity(0.6))
                                                }
                                                .padding(4)
                                                .accessibilityLabel(Text("Remove photo"))
                                            }
                                    }
                                }
                            }
                        }
                    }
                    PhotosPicker(selection: $items, maxSelectionCount: 4, matching: .images) {
                        Label("Add photos (max. 4)", systemImage: "photo.on.rectangle")
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("New message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else {
                        Button("Post") { Task { await post() } }.disabled(!canPost)
                    }
                }
            }
            .sensoryFeedback(.success, trigger: posted)
        }
        .interactiveDismissDisabled(busy || !text.isEmpty)
        .onAppear {
            groupId = preselected?.id ?? model.groups.first?.id
            focused = true
        }
        .onChange(of: items) { _, newItems in
            Task {
                var result: [Data] = []
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self), let jpeg = ImageTools.jpeg(from: data) {
                        result.append(jpeg)
                    }
                }
                images = result
            }
        }
    }

    private var placeholder: LocalizedStringKey {
        switch group?.soort {
        case .weggeef: "What are you giving away? Where can it be picked up?"
        case .markt: "What are you selling, and for how much?"
        case .ondernemers: "Tell your neighbours about your business or an offer"
        case .preventie: "What did you see, where and when?"
        default: "What would you like to share with your neighbours?"
        }
    }

    private func remove(at index: Int) {
        guard images.indices.contains(index) else { return }
        images.remove(at: index)
        if items.indices.contains(index) { items.remove(at: index) }
    }

    private func post() async {
        guard let group, let me = model.userId else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            try await Backend.createPost(group: group, author: me,
                                         body: text.trimmingCharacters(in: .whitespacesAndNewlines), images: images)
            posted += 1
            model.feedVersion += 1
            dismiss()
        } catch {
            self.error = String(localized: "Your message could not be posted. Try again.")
        }
    }
}
