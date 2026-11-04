import SwiftUI

/// Korte animatie na het statische launch screen (zelfde groen en beeldmerk). Wacht nooit op netwerk.
struct SplashView: View {
    var onFinish: () -> Void
    @State private var markScale: CGFloat = 1
    @State private var showWord = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.green.ignoresSafeArea()
            VStack(spacing: 18) {
                BrandMark(style: .onGreen)
                    .frame(width: 120, height: 120)
                    .scaleEffect(markScale)
                (Text(verbatim: "Wijk").foregroundStyle(.white) + Text(verbatim: "Hub").foregroundStyle(Color(red: 0xB9 / 255, green: 0xE0 / 255, blue: 0x8A / 255)))
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .opacity(showWord ? 1 : 0)
                    .offset(y: showWord ? 0 : 8)
            }
            .offset(y: 30) // het launch screen toont het merk iets lager; zo sluit het naadloos aan
        }
        .accessibilityHidden(true)
        .task {
            if reduceMotion {
                showWord = true
                try? await Task.sleep(for: .milliseconds(400))
            } else {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { markScale = 1.12 }
                try? await Task.sleep(for: .milliseconds(180))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { markScale = 1; showWord = true }
                try? await Task.sleep(for: .milliseconds(650))
            }
            onFinish()
        }
    }
}
