import AuthenticationServices
import SwiftUI

struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @State var appleError = false
    @State private var appleNonce = ""

    private let benefits: [(icon: String, title: String, text: String)] = [
        ("graduationcap.fill", "IELTS Speaking и собеседования", "Готовые ответы или свой текст из PDF, Word, фото"),
        ("waveform", "Читаете вслух", "Оценка 0–100 по каждому слову и звуку"),
        ("text.bubble.fill", "Разбор на русском", "Почему звук не так и как сказать правильно"),
        ("calendar", "План до даты", "Обратный отсчёт до экзамена и задание на день")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                BrandMark()
                    .padding(.top, Theme.Spacing.xl)

                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("Подготовьтесь к IELTS Speaking и собеседованию")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Прочитайте свой ответ вслух и узнайте, какие звуки вас выдают — с объяснением на русском.")
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
                        request.requestedScopes = []
                        appleNonce = AppleNonce.make()
                        request.nonce = AppleNonce.sha256(appleNonce)
                    } onCompletion: { result in
                        handleApple(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))

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
        .alert("Не удалось войти через Apple", isPresented: $appleError) {
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
            appleError = true
            return
        }
        let nonce = appleNonce
        appleNonce = ""
        Task {
            do {
                try await APIClient.shared.signInWithApple(identityToken: token, nonce: nonce)
                UserDefaults.standard.set(true, forKey: "sc.appleSignedIn")
                store.hasCompletedOnboarding = true
            } catch {
                appleError = true
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
