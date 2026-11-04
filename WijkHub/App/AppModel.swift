import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable { case loading, signedOut, onboarding, ready }

    var phase: Phase = .loading
    var userId: UUID?
    var email: String?
    var profile: Profile?
    var contact: ProfileContact?
    var wijk: Wijk?
    var membership: WijkMember?
    var groups: [BuurtGroup] = []
    var lastError: String?
    /// Verhoogd na een nieuw bericht, zodat lijsten opnieuw laden.
    var feedVersion = 0
    /// Aantal ongelezen privéberichten (badge op het tabblad Berichten).
    var unreadMessages = 0

    /// Groepen voor de tijdlijn; Marktplaats en Weggeefhoek staan in het tabblad Markt.
    var feedGroups: [BuurtGroup] { groups.filter { $0.soort != .markt && $0.soort != .weggeef } }

    var isAdmin: Bool { membership?.isAdmin == true }

    private var listening = false

    func start() async {
        guard !listening else { return }
        listening = true
        guard SupabaseConfig.isConfigured else {
            phase = .signedOut
            return
        }
        for await (_, session) in Backend.auth.authStateChanges {
            if let session {
                userId = session.user.id
                email = session.user.email
                await reload()
            } else {
                reset()
            }
        }
    }

    func reload() async {
        guard let userId else { reset(); return }
        do {
            let profile = try await Backend.profile(userId)
            self.profile = profile
            contact = try? await Backend.contact(userId)
            if let wijkId = profile.wijkId {
                wijk = try await Backend.wijk(wijkId)
                membership = try await Backend.membership(wijk: wijkId, user: userId)
                groups = try await Backend.groups(wijk: wijkId)
            } else {
                wijk = nil; membership = nil; groups = []
            }
            phase = profile.isComplete && membership != nil ? .ready : .onboarding
        } catch {
            lastError = error.localizedDescription
            if phase == .loading { phase = .onboarding }
        }
    }

    func refreshUnread() async {
        guard phase == .ready, let list = try? await Backend.conversations() else { return }
        unreadMessages = list.reduce(0) { $0 + $1.unread }
    }

    func signOut() async {
        try? await Backend.signOut()
        reset()
    }

    func deleteAccount() async throws {
        try await Backend.deleteAccount()
        reset()
    }

    private func reset() {
        userId = nil; email = nil; profile = nil; contact = nil
        wijk = nil; membership = nil; groups = []
        unreadMessages = 0
        phase = .signedOut
    }
}
