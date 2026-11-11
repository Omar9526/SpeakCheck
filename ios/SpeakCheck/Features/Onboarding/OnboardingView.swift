import AuthenticationServices
import OSLog
import SwiftUI

struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @State var signInError = false
    @State private var googleInProgress = false
    @State private var appleNonce = ""

    private let benefits: [(icon: String, title: String, text: String)] = [
        ("doc.text.fill", "Любой английский текст", "Свой из PDF, Word, фото — или готовые ответы"),
        ("waveform", "Читаете вслух", "Оценка 0–100 по каждому слову и звуку"),
        ("text.bubble.fill", "Разбор на русском", "Почему звук не так и как сказать правильно"),
        ("target", "Под вашу цель", "Экзамен IELTS, собеседование или просто увереннее говорить")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                BrandMark()
                    .padding(.top, Theme.Spacing.xl)

                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("Говорите по-английски чисто и уверенно")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Читайте вслух любой английский текст и узнайте, какие звуки вас выдают — с объяснением на русском.")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                VStack(spacing: Theme.Spacing.s) {
                    ForEach(benefits, id: \.title) { item in
                        HStack(spacing: Theme.Spacing.m) {
                            IconTile(systemName: item.icon)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.headline).foregroundStyle(Theme.Colors.textPrimary)
                                Text(item.text).font(.subheadline).foregroundStyle(Theme.Colors.textSecondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .card(padding: Theme.Spacing.m, radius: Theme.Radius.medium)
                        .accessibilityElement(children: .combine)
                    }
                }

                VStack(spacing: Theme.Spacing.m) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName]
                        appleNonce = AppleNonce.make()
                        request.nonce = AppleNonce.sha256(appleNonce)
                    } onCompletion: { result in
                        handleApple(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))

                    if GoogleAuth.isConfigured {
                        Button(action: signInWithGoogle) {
                            HStack(spacing: 10) {
                                if googleInProgress {
                                    ProgressView().tint(.black)
                                } else {
                                    Image("GoogleLogo").resizable().frame(width: 18, height: 18)
                                }
                                Text("Вход с Google")
                                    .font(.system(size: 19, weight: .medium))
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(.white, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(googleInProgress)
                        .accessibilityLabel("Вход с Google")
                    }

                    Button("Попробовать без входа") {
                        store.hasCompletedOnboarding = true
                        // Гостевой аккаунт на сервере создаётся лениво при первой оценке.
                    }
                    .buttonStyle(.secondary)

                    Text("Без входа история привязана к этому iPhone. Оценка не является сертифицированным тестом CEFR.")
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .alert("Не удалось войти", isPresented: $signInError) {
            Button("Продолжить без входа") { store.hasCompletedOnboarding = true }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Проверьте подключение к интернету или продолжите без входа — данные сохранятся на iPhone.")
        }
        .background(ScreenBackground())
    }
}

extension OnboardingView {
    func handleApple(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let auth) = result,
              let credential = auth.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8), !appleNonce.isEmpty else {
            signInError = true
            return
        }
        let nonce = appleNonce
        appleNonce = ""
        let fullName = credential.fullName.flatMap { PersonNameComponentsFormatter().string(from: $0) }
            .flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        Task {
            do {
                try await APIClient.shared.signInWithApple(identityToken: token, nonce: nonce)
                SignInProvider.current = .apple
                if let fullName { AccountProfile.current = AccountProfile(name: fullName) }
                store.hasCompletedOnboarding = true
            } catch {
                signInError = true
            }
        }
    }

    func signInWithGoogle() {
        googleInProgress = true
        Task {
            defer { googleInProgress = false }
            do {
                try await GoogleAuth.signIn()
                SignInProvider.current = .google
                store.hasCompletedOnboarding = true
            } catch where GoogleAuth.isCancellation(error) {
                // Пользователь закрыл окно Google — остаёмся на экране без ошибки.
                Logger.auth.info("google sign-in cancelled")
            } catch {
                Logger.auth.error("google sign-in failed: \(String(describing: error), privacy: .public)")
                signInError = true
            }
        }
    }
}

/// Логотип: волна + название.
struct BrandMark: View {
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(Theme.Colors.accentGradient)
            Text("SpeakCheck")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("SpeakCheck")
    }
}

#Preview {
    OnboardingView().environment(AppStore(persists: false))
}

extension Logger {
    static let auth = Logger(subsystem: "kg.speakcheck.app", category: "auth")
}
