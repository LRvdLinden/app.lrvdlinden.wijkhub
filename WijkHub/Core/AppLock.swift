import SwiftUI
import LocalAuthentication

/// Face ID / Touch ID-vergrendeling. Aan/uit in Instellingen.
@MainActor
@Observable
final class AppLock {
    var isLocked: Bool
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "lock.enabled")
            if !isEnabled { isLocked = false }
        }
    }

    init() {
        let enabled = UserDefaults.standard.bool(forKey: "lock.enabled")
        isEnabled = enabled
        isLocked = enabled
    }

    static var biometryAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func lockIfNeeded() {
        if isEnabled { isLocked = true }
    }

    func unlock() async {
        guard isLocked else { return }
        let context = LAContext()
        let reason = String(localized: "Unlock WijkHub")
        do {
            if try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) {
                isLocked = false
            }
        } catch {
            // Blijft vergrendeld; de gebruiker kan het opnieuw proberen.
        }
    }

    /// Vraagt eerst Face ID voordat de schakelaar aan gaat.
    func enable() async -> Bool {
        let context = LAContext()
        let reason = String(localized: "Unlock WijkHub")
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
        if ok { isEnabled = true }
        return ok
    }
}

struct LockView: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        ZStack {
            Theme.green.ignoresSafeArea()
            VStack(spacing: 24) {
                BrandMark(style: .onGreen)
                    .frame(width: 96, height: 96)
                Text("WijkHub is locked")
                    .font(.app(.title3, .semibold))
                    .foregroundStyle(.white)
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label("Unlock", systemImage: "faceid")
                        .font(.app(.headline))
                        .padding(.horizontal, 24).padding(.vertical, 12)
                        .background(.white, in: Capsule())
                        .foregroundStyle(Theme.green)
                }
                .buttonStyle(.plain)
            }
        }
        .task { await lock.unlock() }
    }
}
