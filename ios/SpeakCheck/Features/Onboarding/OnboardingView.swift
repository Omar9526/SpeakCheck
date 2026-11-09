import AuthenticationServices
import SwiftUI

struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @State var appleError = false

    private let benefits: [(icon: String, title: String, text: String)] = [
        ("doc.text.fill", "Свой текст", "PDF, Word, TXT или фото страницы"),
        ("waveform", "Читаете вслух", "Запись прямо в приложении"),
        ("chart.pie.fill", "Оценка 0–100", "Произношение, беглость, точность"),
        ("text.bubble.fill", "Разбор ошибок", "Объяснения на русском и повтор слова")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                BrandMark()
                    .padding(.top, Theme.Spacing.xl)

                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("Говорите по-английски увереннее")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Загрузите любой английский текст, прочитайте его вслух и узнайте, какие слова звучат неправильно.")
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

                    Text("Без входа данные хранятся только на этом iPhone. Оценка не является сертифицированным тестом CEFR.")
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
              let token = String(data: tokenData, encoding: .utf8) else {
            appleError = true
            return
        }
        Task {
            do {
                try await APIClient.shared.signInWithApple(identityToken: token)
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
