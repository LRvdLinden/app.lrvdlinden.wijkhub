import SwiftUI

enum ReportTarget: Identifiable, Hashable {
    case post(UUID, wijk: UUID)
    case comment(UUID, wijk: UUID)
    case profile(UUID, wijk: UUID)
    case listing(UUID, wijk: UUID)
    case help(UUID, wijk: UUID)

    var id: String {
        switch self {
        case .post(let id, _): "p-\(id)"
        case .comment(let id, _): "c-\(id)"
        case .profile(let id, _): "u-\(id)"
        case .listing(let id, _): "l-\(id)"
        case .help(let id, _): "h-\(id)"
        }
    }
}

struct ReportSheet: View {
    let target: ReportTarget
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    enum Reason: String, CaseIterable, Identifiable {
        case spam, offensive, personal, unsafe, other
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self {
            case .spam: "Spam or advertising"
            case .offensive: "Offensive or discriminating"
            case .personal: "Shares someone's personal details"
            case .unsafe: "Threatening or unsafe"
            case .other: "Something else"
            }
        }
    }

    @State private var reason: Reason = .spam
    @State private var note = ""
    @State private var busy = false
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Why are you reporting this?") {
                    Picker("Reason", selection: $reason) {
                        ForEach(Reason.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Explanation (optional)") {
                    TextField("What is going on?", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section {
                    Text("The administrators of your neighbourhood will look at your report. The person you report will not see who reported it.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { Task { await send() } }.disabled(busy)
                }
            }
            .sensoryFeedback(.success, trigger: sent)
        }
        .presentationDetents([.medium, .large])
    }

    private func send() async {
        guard let me = model.userId else { return }
        busy = true
        defer { busy = false }
        let english: String = switch reason {
        case .spam: "spam"
        case .offensive: "beledigend"
        case .personal: "persoonsgegevens"
        case .unsafe: "bedreigend"
        case .other: "anders"
        }
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let reden = text.isEmpty ? english : "\(english): \(text)"
        var report: Backend.NewReport
        switch target {
        case .post(let id, let wijk): report = .init(wijk_id: wijk, reporter_id: me, post_id: id, reden: reden)
        case .comment(let id, let wijk): report = .init(wijk_id: wijk, reporter_id: me, comment_id: id, reden: reden)
        case .profile(let id, let wijk): report = .init(wijk_id: wijk, reporter_id: me, profile_id: id, reden: reden)
        case .listing(let id, let wijk): report = .init(wijk_id: wijk, reporter_id: me, listing_id: id, reden: reden)
        case .help(let id, let wijk): report = .init(wijk_id: wijk, reporter_id: me, help_id: id, reden: reden)
        }
        do {
            try await Backend.report(report)
            sent = true
            dismiss()
        } catch {
            model.lastError = error.localizedDescription
        }
    }
}
