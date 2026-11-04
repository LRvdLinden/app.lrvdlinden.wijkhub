import SwiftUI

@main
struct WijkHubApp: App {
    @State private var model = AppModel()
    @State private var lock = AppLock()
    @AppStorage("ui.appearance") private var appearance: AppearanceSetting = .system

    init() { BrandAppearance.apply() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(lock)
                .font(.app(.body))
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppLock.self) private var lock
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true

    var body: some View {
        ZStack {
            switch model.phase {
            case .loading:
                Theme.green.ignoresSafeArea()
            case .signedOut:
                SignInView()
            case .onboarding:
                OnboardingView()
            case .ready:
                MainTabView()
            }

            if lock.isLocked && model.phase != .signedOut {
                LockView().transition(.opacity)
            }
            if showSplash {
                SplashView { withAnimation(.easeOut(duration: 0.25)) { showSplash = false } }
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.default, value: model.phase)
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { lock.lockIfNeeded() }
        }
        .onOpenURL { _ in
            // wijkhub://… — deep links volgen in fase 4 (meldingen, widgets).
        }
        .reviewPrompt(isCalm: model.phase == .ready && !lock.isLocked && !showSplash)
    }
}
