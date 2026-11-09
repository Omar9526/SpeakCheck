import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("sc.keepAudio") private var keepAudio = false
    @AppStorage("sc.explanationLanguage") private var explanationLanguage = "ru"
    @AppStorage("sc.voiceConsent") private var voiceConsent = false
    @State private var confirmErase = false

    var body: some View {
        List {
            Section {
                HStack(spacing: Theme.Spacing.m) {
                    IconTile(systemName: "person.fill", size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(UserDefaults.standard.bool(forKey: "sc.appleSignedIn") ? "Вход через Apple" : "Гостевой режим")
                            .font(.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(UserDefaults.standard.bool(forKey: "sc.appleSignedIn") ? "История сохраняется в аккаунте" : "Данные хранятся только на этом iPhone")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Обучение") {
                Picker("Язык объяснений", selection: $explanationLanguage) {
                    Text("Русский").tag("ru")
                    Text("English").tag("en")
                }
                LabeledContent("Язык чтения", value: "English")
            }

            Section {
                Toggle("Хранить мои записи", isOn: $keepAudio)
                Toggle("Согласие на обработку голоса", isOn: $voiceConsent)
            } header: {
                Text("Приватность")
            } footer: {
                Text("Для оценки запись отправляется на наш сервер и в Microsoft Azure Speech. По умолчанию аудио удаляется сразу после анализа. Объяснения ошибок формируются по текстовым результатам — без аудио.")
            }

            Section {
                Button("Удалить все мои данные", role: .destructive) { confirmErase = true }
                Button("Выйти") {
                    TokenStore.clear()
                    UserDefaults.standard.set(false, forKey: "sc.appleSignedIn")
                    store.hasCompletedOnboarding = false
                }
                    .foregroundStyle(Theme.Colors.textPrimary)
            } footer: {
                Text("SpeakCheck \(Bundle.main.appVersion) · Оценки — учебный ориентир, а не сертифицированный тест CEFR.")
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Профиль")
        .confirmationDialog("Удалить все документы, попытки и записи?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Удалить всё", role: .destructive) {
                store.eraseAll()
                try? FileManager.default.removeItem(at: AudioRecorder.draftsDirectory)
                // Удаление аккаунта и всех данных на сервере (DELETE /me).
                Task {
                    if TokenStore.accessToken != nil { try? await APIClient.shared.delete("me") }
                    TokenStore.clear()
                }
            }
        }
    }
}

extension Bundle {
    var appVersion: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}

#if DEBUG
#Preview {
    NavigationStack { SettingsView() }
        .environment(AppStore.demo())
}
#endif
