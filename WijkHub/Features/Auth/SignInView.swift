import SwiftUI
import AuthenticationServices
import CryptoKit

struct SignInView: View {
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var busy = false
    @State private var error: String?
    @State private var nonce = ""
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var emailValid: Bool {
        let e = email.trimmingCharacters(in: .whitespaces)
        return e.contains("@") && e.contains(".") && e.count >= 6
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 14) {
                    BrandLogo(markSize: 56)
                    Text("Everything from your neighbourhood in one place")
                        .font(.app(.title3))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 48)

                if !SupabaseConfig.isConfigured {
                    Label("The server is not connected yet.", systemImage: "exclamationmark.triangle")
                        .font(.app(.footnote))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.tint, in: RoundedRectangle(cornerRadius: 12))
                }

                VStack(spacing: 12) {
                    if !codeSent {
                        TextField("E-mail address", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .submitLabel(.send)
                            .onSubmit { Task { await sendCode() } }
                            .fieldStyle()
                        Button { Task { await sendCode() } } label: {
                            ProgressLabel(title: "Send login code", busy: busy)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!emailValid || busy)
                    } else {
                        Text("We sent a code to \(email). Enter it below.")
                            .font(.app(.subheadline))
                            .multilineTextAlignment(.center)
                        TextField("6-digit code", text: $code)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)
                            .focused($focused)
                            .fieldStyle()
                            .onChange(of: code) { _, new in
                                code = String(new.filter(\.isNumber).prefix(8))
                                if code.count == 6 { Task { await verify() } }
                            }
                        Button { Task { await verify() } } label: {
                            ProgressLabel(title: "Log in", busy: busy)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(code.count < 6 || busy)
                        Button("Use another e-mail address") {
                            codeSent = false; code = ""; error = nil
                        }
                        .font(.app(.subheadline))
                    }
                }

                HStack {
                    Rectangle().fill(Theme.line).frame(height: 1)
                    Text("or").font(.app(.footnote)).foregroundStyle(.secondary)
                    Rectangle().fill(Theme.line).frame(height: 1)
                }

                SignInWithAppleButton(.continue) { request in
                    nonce = Self.randomNonce()
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = Self.sha256(nonce)
                } onCompletion: { result in
                    Task { await handleApple(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let error {
                    Text(error)
                        .font(.app(.footnote))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
    }

    private func sendCode() async {
        guard emailValid else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            try await Backend.sendEmailCode(email.trimmingCharacters(in: .whitespaces).lowercased())
            codeSent = true
            focused = true
        } catch {
            self.error = String(localized: "Could not send the code. Check the address and try again.")
        }
    }

    private func verify() async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            try await Backend.verifyEmailCode(email.trimmingCharacters(in: .whitespaces).lowercased(), code: code)
        } catch {
            self.error = String(localized: "That code is not correct or has expired.")
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else { return }
            busy = true
            defer { busy = false }
            do {
                try await Backend.signInWithApple(idToken: token, nonce: nonce)
                // Apple geeft de naam alleen de eerste keer; bewaar hem als voorstel voor de onboarding.
                if let name = credential.fullName {
                    let full = PersonNameComponentsFormatter().string(from: name)
                    if !full.isEmpty { UserDefaults.standard.set(full, forKey: "onboarding.suggestedName") }
                }
            } catch {
                self.error = String(localized: "Signing in with Apple did not work. Try again.")
            }
        case .failure(let err):
            if (err as? ASAuthorizationError)?.code != .canceled {
                self.error = String(localized: "Signing in with Apple did not work. Try again.")
            }
        }
    }

    static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in chars[Int.random(in: 0..<chars.count, using: &generator)] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Gedeelde stijlen

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.app(.headline))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.accent.opacity(isEnabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(Theme.onAccent)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct ProgressLabel: View {
    let title: LocalizedStringKey
    let busy: Bool

    var body: some View {
        if busy { ProgressView().tint(Theme.onAccent) } else { Text(title) }
    }
}

extension View {
    func fieldStyle() -> some View {
        padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
    }
}
