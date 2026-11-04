import SwiftUI
import PhotosUI

/// Na het inloggen: naam (+ foto), contact, wijk en huisregels. Alleen wat nog ontbreekt wordt gevraagd.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    enum Step: Int, CaseIterable { case name, contact, wijk, rules }

    @State private var step: Step = .name
    @State private var name = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var phone = ""
    @State private var phoneVisible = false
    @State private var wijken: [Wijk] = []
    @State private var selectedWijk: Wijk?
    @State private var search = ""
    @State private var agreed = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count))
                    .tint(Theme.accent)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .accessibilityLabel(Text("Step \(step.rawValue + 1) of \(Step.allCases.count)"))

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch step {
                        case .name: nameStep
                        case .contact: contactStep
                        case .wijk: wijkStep
                        case .rules: rulesStep
                        }
                        if let error {
                            Text(error).font(.app(.footnote)).foregroundStyle(.red)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 560, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)

                HStack(spacing: 12) {
                    if step != .name {
                        Button("Back") { withAnimation { step = Step(rawValue: step.rawValue - 1) ?? .name } }
                            .frame(minHeight: 50)
                            .padding(.horizontal, 12)
                    }
                    Button { Task { await next() } } label: {
                        ProgressLabel(title: step == .rules ? "Start" : "Next", busy: busy)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canContinue || busy)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .frame(maxWidth: 560)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Log out") { Task { await model.signOut() } }
                }
            }
        }
        .task { await prepare() }
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    photoData = ImageTools.jpeg(from: data, maxSide: 600)
                }
            }
        }
    }

    // MARK: Stappen

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: "What is your name?", text: "Your neighbours see this name with your messages.")
            HStack {
                Spacer()
                PhotosPicker(selection: $photoItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        if let photoData, let image = UIImage(data: photoData) {
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: 96, height: 96).clipShape(Circle())
                        } else {
                            Avatar(path: nil, name: name, size: 96)
                        }
                        Image(systemName: "camera.fill")
                            .font(.app(.footnote))
                            .padding(7)
                            .background(Theme.accent, in: Circle())
                            .foregroundStyle(Theme.onAccent)
                    }
                }
                .accessibilityLabel(Text("Choose profile photo"))
                Spacer()
            }
            TextField("First and last name", text: $name)
                .textContentType(.name)
                .fieldStyle()
        }
    }

    private var contactStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: "How can neighbours reach you?", text: "Your e-mail address stays private. Your mobile number is optional.")
            if let email = model.email {
                LabeledContent("E-mail address", value: email)
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            }
            TextField("Mobile number (optional)", text: $phone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .fieldStyle()
            Toggle("Show my number to neighbours", isOn: $phoneVisible)
                .disabled(phone.trimmingCharacters(in: .whitespaces).isEmpty)
                .tint(Theme.accent)
        }
    }

    private var wijkStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: "Which neighbourhood do you live in?", text: "You see the groups and messages of your own neighbourhood.")
            TextField("Search by name, town or postcode", text: $search)
                .fieldStyle()
            if wijken.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            }
            ForEach(filteredWijken) { wijk in
                Button { selectedWijk = wijk } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(wijk.naam).font(.app(.headline))
                            Text(wijk.plaats).font(.app(.subheadline)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: selectedWijk == wijk ? "checkmark.circle.fill" : "circle")
                            .font(.app(.title3))
                            .foregroundStyle(selectedWijk == wijk ? Theme.accent : Color.secondary)
                    }
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selectedWijk == wijk ? Theme.accent : Theme.line))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: selectedWijk)
            }
            if !wijken.isEmpty && filteredWijken.isEmpty {
                Text("No neighbourhood found. Ask your neighbourhood council to add it.")
                    .font(.app(.subheadline)).foregroundStyle(.secondary)
            }
        }
    }

    private var rulesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: "House rules", text: "WijkHub is for and by neighbours. That only works if we treat each other well.")
            VStack(alignment: .leading, spacing: 12) {
                RuleRow(symbol: "heart", text: "Be friendly and respectful, also when you disagree.")
                RuleRow(symbol: "hand.raised", text: "No discrimination, threats, spam or personal attacks.")
                RuleRow(symbol: "eye.slash", text: "Don't share other people's personal details or photos without permission.")
                RuleRow(symbol: "phone.arrow.up.right", text: "In an emergency, always call 112 first. WijkHub is not an emergency service.")
                RuleRow(symbol: "flag", text: "Report messages that break the rules. The administrators can remove them and block people.")
            }
            if let terms = AppLinks.terms {
                Link("Read the full terms of use", destination: terms).font(.app(.subheadline))
            }
            Toggle("I agree to the house rules and terms of use", isOn: $agreed)
                .tint(Theme.accent)
        }
    }

    // MARK: Logica

    private var canContinue: Bool {
        switch step {
        case .name: name.trimmingCharacters(in: .whitespaces).count >= 2
        case .contact: true
        case .wijk: selectedWijk != nil
        case .rules: agreed
        }
    }

    private var filteredWijken: [Wijk] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return wijken }
        return wijken.filter {
            $0.naam.lowercased().contains(q) || $0.plaats.lowercased().contains(q)
                || $0.postcodes.contains { $0.hasPrefix(String(q.prefix(4))) }
        }
    }

    private func prepare() async {
        if let profile = model.profile {
            name = profile.displayName
            if name.isEmpty { name = UserDefaults.standard.string(forKey: "onboarding.suggestedName") ?? "" }
        }
        if let contact = model.contact {
            phone = contact.telefoon
            phoneVisible = contact.telefoonZichtbaar
        }
        wijken = (try? await Backend.wijken()) ?? []
        if let id = model.profile?.wijkId { selectedWijk = wijken.first { $0.id == id } }
        if wijken.count == 1, selectedWijk == nil { selectedWijk = wijken.first }
    }

    private func next() async {
        guard let userId = model.userId else { return }
        error = nil
        busy = true
        defer { busy = false }
        do {
            switch step {
            case .name:
                var avatar = model.profile?.avatarPath
                if let photoData { avatar = try await Backend.uploadImage(photoData, owner: userId) }
                try await Backend.updateProfile(userId, name: name.trimmingCharacters(in: .whitespaces),
                                                bio: model.profile?.bio ?? "", straat: model.profile?.straat ?? "",
                                                avatarPath: avatar)
                withAnimation { step = .contact }
            case .contact:
                let p = phone.trimmingCharacters(in: .whitespaces)
                try await Backend.updateContact(userId, phone: p, visible: !p.isEmpty && phoneVisible)
                withAnimation { step = .wijk }
            case .wijk:
                if let selectedWijk { try await Backend.joinWijk(selectedWijk.id) }
                withAnimation { step = .rules }
            case .rules:
                try await Backend.acceptRules(userId)
                UserDefaults.standard.removeObject(forKey: "onboarding.suggestedName")
                await model.reload()
            }
        } catch {
            self.error = String(localized: "Something went wrong. Check your connection and try again.")
        }
    }
}

private struct StepHeader: View {
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.display(.title2))
            Text(text).font(.app(.body)).foregroundStyle(.secondary)
        }
    }
}

private struct RuleRow: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            Text(text)
        }
    }
}
