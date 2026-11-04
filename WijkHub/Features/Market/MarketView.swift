import SwiftUI

/// Tabblad Markt: te koop en gratis (weggeefhoek) in één overzicht.
struct MarketView: View {
    @Environment(AppModel.self) private var model
    @State private var listings: [Listing] = []
    @State private var filter: Filter = .all
    @State private var category: ListingCategory?
    @State private var showSold = false
    @State private var search = ""
    @State private var loading = false
    @State private var failed = false
    @State private var creating = false

    enum Filter: String, CaseIterable, Identifiable {
        case all, markt, weggeef, mine
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self { case .all: "All"; case .markt: "For sale"; case .weggeef: "Free"; case .mine: "Mine" }
        }
    }

    private var visible: [Listing] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return listings.filter { l in
            switch filter {
            case .all: true
            case .markt: l.soort == .markt
            case .weggeef: l.soort == .weggeef
            case .mine: l.authorId == model.userId
            }
        }
        .filter { showSold || filter == .mine || $0.status != .verkocht }
        .filter { category == nil || $0.category == category }
        .filter { q.isEmpty || $0.titel.lowercased().contains(q) || $0.beschrijving.lowercased().contains(q) }
    }

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 260), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Chip(title: "All categories", symbol: "square.grid.2x2", selected: category == nil) { category = nil }
                        ForEach(ListingCategory.allCases) { c in
                            Chip(title: c.label, symbol: c.symbol, selected: category == c) { category = category == c ? nil : c }
                        }
                    }
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(visible) { listing in
                        NavigationLink(value: listing) {
                            ListingCard(listing: listing)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .searchable(text: $search, prompt: Text("Search the market"))
        .overlay {
            if visible.isEmpty {
                if loading && listings.isEmpty {
                    ProgressView()
                } else if failed && listings.isEmpty {
                    ContentUnavailableView {
                        Label("Could not load the market", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text("Check your internet connection.")
                    } actions: {
                        Button("Try again") { Task { await load() } }
                    }
                } else {
                    ContentUnavailableView {
                        Label("Nothing here yet", systemImage: "tag")
                    } description: {
                        Text("Sell or give away something you no longer need.")
                    } actions: {
                        Button("Place an ad") { creating = true }
                    }
                }
            }
        }
        .navigationTitle("Market")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel(Text("Place an ad"))
            }
            ToolbarItem(placement: .secondaryAction) {
                Toggle("Show sold items", isOn: $showSold)
            }
        }
        .sheet(isPresented: $creating) { ListingEditor(existing: nil) }
        .refreshable { await load() }
        .task(id: model.feedVersion) { await load() }
    }

    private func load() async {
        guard let wijk = model.wijk?.id else { return }
        loading = true; failed = false
        defer { loading = false }
        do {
            listings = try await Backend.listings(wijk: wijk)
        } catch is CancellationError {
        } catch {
            failed = true
        }
    }
}

struct Chip: View {
    let title: LocalizedStringKey
    var symbol: String?
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(selected ? Theme.accent : Theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Theme.line))
            .foregroundStyle(selected ? Theme.onAccent : Color.primary)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ListingCard: View {
    let listing: Listing

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.secondary.opacity(0.12)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let path = listing.imagePaths.first, let url = Backend.publicURL(path) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() } else { ProgressView() }
                        }
                    } else {
                        Image(systemName: listing.category.symbol)
                            .font(.largeTitle)
                            .foregroundStyle(Theme.accent.opacity(0.6))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if listing.status != .beschikbaar {
                        StatusBadge(status: listing.status, kind: listing.soort).padding(8)
                    }
                }
                .opacity(listing.status == .verkocht ? 0.55 : 1)
            Text(listing.titel)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(listing.priceText)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.accent)
        }
        .accessibilityElement(children: .combine)
    }
}

struct StatusBadge: View {
    let status: ListingStatus
    let kind: ListingKind

    var body: some View {
        Text(status.label(for: kind))
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(status == .verkocht ? Color.black.opacity(0.7) : Color.orange, in: Capsule())
            .foregroundStyle(.white)
    }
}
