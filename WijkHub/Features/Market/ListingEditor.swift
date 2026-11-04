import SwiftUI
import PhotosUI

struct ListingEditor: View {
    let existing: Listing?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ListingKind = .markt
    @State private var titel = ""
    @State private var beschrijving = ""
    @State private var priceType: PriceType = .vast
    @State private var priceText = ""
    @State private var category: ListingCategory = .overig
    @State private var keptPaths: [String] = []
    @State private var items: [PhotosPickerItem] = []
    @State private var newImages: [Data] = []
    @State private var busy = false
    @State private var error: String?
    @State private var saved = 0

    private let maxPhotos = 6

    private var priceCents: Int? {
        let cleaned = priceText.replacingOccurrences(of: "€", with: "").replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value >= 0 else { return nil }
        return Int((value * 100).rounded())
    }

    private var canSave: Bool {
        guard titel.trimmingCharacters(in: .whitespaces).count >= 2, !busy else { return false }
        if kind == .markt && priceType == .vast { return priceCents != nil }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        Text("Sell").tag(ListingKind.markt)
                        Text("Give away").tag(ListingKind.weggeef)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section("What is it?") {
                    TextField("Title", text: $titel)
                    TextField("Description: condition, size, where to pick it up", text: $beschrijving, axis: .vertical)
                        .lineLimit(3...10)
                    Picker("Category", selection: $category) {
                        ForEach(ListingCategory.allCases) { c in
                            Label(c.label, systemImage: c.symbol).tag(c)
                        }
                    }
                }
                if kind == .markt {
                    Section("Price") {
                        Picker("Price", selection: $priceType) {
                            Text("Fixed price").tag(PriceType.vast)
                            Text("Make an offer").tag(PriceType.bieden)
                        }
                        .pickerStyle(.segmented)
                        HStack {
                            Text(verbatim: "€")
                            TextField(priceType == .vast ? LocalizedStringKey("Price") : LocalizedStringKey("Starting from (optional)"),
                                      text: $priceText)
                                .keyboardType(.decimalPad)
                        }
                    }
                }
                Section {
                    photoStrip
                    if keptPaths.count + newImages.count < maxPhotos {
                        PhotosPicker(selection: $items, maxSelectionCount: maxPhotos - keptPaths.count, matching: .images) {
                            Label("Add photos (max. 6)", systemImage: "photo.on.rectangle")
                        }
                    }
                } header: {
                    Text("Photos")
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle(existing == nil ? LocalizedStringKey("Place an ad") : LocalizedStringKey("Edit ad"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else {
                        Button(existing == nil ? LocalizedStringKey("Post") : LocalizedStringKey("Save")) { Task { await save() } }
                            .disabled(!canSave)
                    }
                }
            }
            .sensoryFeedback(.success, trigger: saved)
        }
        .interactiveDismissDisabled(busy)
        .onAppear(perform: fill)
        .onChange(of: items) { _, newItems in
            Task {
                var result: [Data] = []
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self), let jpeg = ImageTools.jpeg(from: data) {
                        result.append(jpeg)
                    }
                }
                newImages = result
            }
        }
    }

    @ViewBuilder private var photoStrip: some View {
        if !keptPaths.isEmpty || !newImages.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(keptPaths, id: \.self) { path in
                        AsyncImage(url: Backend.publicURL(path)) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() } else { Color.secondary.opacity(0.15) }
                        }
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .topTrailing) {
                            RemoveButton { keptPaths.removeAll { $0 == path } }
                        }
                    }
                    ForEach(newImages.indices, id: \.self) { i in
                        if let ui = UIImage(data: newImages[i]) {
                            Image(uiImage: ui).resizable().scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(alignment: .topTrailing) {
                                    RemoveButton {
                                        newImages.remove(at: i)
                                        if items.indices.contains(i) { items.remove(at: i) }
                                    }
                                }
                        }
                    }
                }
            }
        }
    }

    private func fill() {
        guard let l = existing else { return }
        kind = l.soort
        titel = l.titel
        beschrijving = l.beschrijving
        priceType = l.prijsType == .gratis ? .vast : l.prijsType
        if let c = l.prijsCent { priceText = c % 100 == 0 ? String(c / 100) : String(format: "%.2f", Double(c) / 100).replacingOccurrences(of: ".", with: ",") }
        category = l.category
        keptPaths = l.imagePaths
    }

    private func save() async {
        guard let me = model.userId, let wijk = model.wijk?.id else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            var paths = keptPaths
            for data in newImages.prefix(maxPhotos - keptPaths.count) {
                paths.append(try await Backend.uploadImage(data, owner: me))
            }
            let type: PriceType = kind == .weggeef ? .gratis : priceType
            let cents: Int? = kind == .weggeef ? nil : priceCents
            let write = Backend.ListingWrite(
                wijk_id: existing?.wijkId ?? wijk, author_id: existing?.authorId ?? me, soort: kind.rawValue,
                titel: titel.trimmingCharacters(in: .whitespaces),
                beschrijving: beschrijving.trimmingCharacters(in: .whitespacesAndNewlines),
                prijs_type: type.rawValue, prijs_cent: cents, categorie: category.rawValue, image_paths: paths)
            try await Backend.saveListing(id: existing?.id, write)
            saved += 1
            model.feedVersion += 1
            dismiss()
        } catch {
            self.error = String(localized: "Your ad could not be saved. Try again.")
        }
    }
}

struct RemoveButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.6))
        }
        .buttonStyle(.plain)
        .padding(4)
        .accessibilityLabel(Text("Remove photo"))
    }
}
