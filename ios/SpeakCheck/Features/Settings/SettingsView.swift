import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("sc.keepAudio") private var keepAudio = false
    @AppStorage("sc.explanationLanguage") private var explanationLanguage = "ru"
    @AppStorage("sc.voiceConsent") private var voiceConsent = false
    @AppStorage(ReferenceVoice.storageKey) private var referenceVoice = ReferenceVoice.bella.rawValue
    @State private var speech = SpeechPlayer()
    @State private var previewing: ReferenceVoice?
    @State private var confirmErase = false
    @State private var profileVersion = 0  // перерисовать шапку после восстановления профиля

    var body: some View {
        List {
            Section {
                accountHeader
                    .id(profileVersion)
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
                ForEach(ReferenceVoice.allCases) { voice in
                    voiceRow(voice)
                }
            } header: {
                Text("Голос образца")
            } footer: {
                Text("Этим голосом звучит «Послушать» — как правильно произносить фрагмент или слово.")
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
                    Task { await APIClient.shared.logout() }
                    if SignInProvider.current == .google { GoogleAuth.signOut() }
                    SignInProvider.current = nil
                    store.hasCompletedOnboarding = false
                }
                    .foregroundStyle(Theme.Colors.textPrimary)
            } footer: {
                Text("SpeakCheck \(Bundle.main.appVersion) · Оценки — учебный ориентир, а не сертифицированный тест CEFR.")
            }
        }
        .task {
            guard SignInProvider.current == .google, AccountProfile.current == nil,
                  let profile = await GoogleAuth.restoreProfile() else { return }
            AccountProfile.current = profile
            profileVersion += 1
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Профиль")
        // Настройки приватности должны доходить до сервера: он решает, хранить ли запись.
        .onChange(of: keepAudio) { _, new in ProfileSync.push(.init(keepAudio: new)) }
        .onChange(of: voiceConsent) { _, new in ProfileSync.push(.init(voiceConsent: new)) }
        .onChange(of: explanationLanguage) { _, new in ProfileSync.push(.init(explanationLanguage: new)) }
        .confirmationDialog("Удалить все документы, попытки и записи?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Удалить всё", role: .destructive) {
                store.eraseAll()
                if SignInProvider.current == .google { GoogleAuth.signOut() }
                SignInProvider.current = nil
                try? FileManager.default.removeItem(at: AudioRecorder.draftsDirectory)
                PendingUploads.shared.clear()
                PracticeStock.shared.clear()
                // Удаление аккаунта и всех данных на сервере (DELETE /me).
                Task {
                    if TokenStore.accessToken != nil { try? await APIClient.shared.delete("me") }
                    TokenStore.clear()
                }
            }
        }
    }
}

private extension SettingsView {
    var accountHeader: some View {
        var provider = SignInProvider.current
        var profile = provider != nil ? AccountProfile.current : nil
        #if DEBUG
        // Скриншоты для App Store (-demoData): вымышленный профиль вместо настоящего аккаунта разработчика.
        if ProcessInfo.processInfo.arguments.contains("-demoData") {
            provider = .apple
            profile = AccountProfile(name: "Айгерим Асанова", email: nil, avatarURL: nil)
        }
        #endif
        let title = profile?.name ?? provider?.title ?? "Гостевой режим"
        let subtitle: String = {
            guard let provider else { return "История привязана к этому iPhone — войдите, чтобы не потерять её" }
            let via = "Через \(provider.shortName)"
            if let email = profile?.email { return "\(via) · \(email)" }
            return profile?.name != nil ? via : "История сохраняется в аккаунте"
        }()
        return HStack(spacing: Theme.Spacing.m) {
            avatar(profile)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    func avatar(_ profile: AccountProfile?) -> some View {
        let placeholder = Group {
            if let initials = profile?.initials, !initials.isEmpty {
                Text(initials)
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.accentLight)
                    .frame(width: 48, height: 48)
                    .background(Theme.Colors.accentLight.opacity(0.15), in: Circle())
            } else {
                IconTile(systemName: "person.fill", size: 48)
            }
        }
        if let raw = profile?.avatarURL, let url = URL(string: raw) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                placeholder
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
        } else {
            placeholder
        }
    }

    func voiceRow(_ voice: ReferenceVoice) -> some View {
        let selected = referenceVoice == voice.rawValue
        let playing = previewing == voice && speech.isSpeaking
        return HStack(spacing: Theme.Spacing.m) {
            Button {
                referenceVoice = voice.rawValue
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? Theme.Colors.accentLight : Theme.Colors.textTertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(voice.name).font(.body.weight(.semibold)).foregroundStyle(Theme.Colors.textPrimary)
                        Text(voice.detail).font(.caption).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])

            Button {
                if playing { speech.stop() } else {
                    previewing = voice
                    speech.speak(ReferenceVoice.sample, voice: voice)
                }
            } label: {
                Image(systemName: playing ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.Colors.accentLight)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(playing ? "Остановить" : "Прослушать \(voice.name)")
        }
        .padding(.vertical, 2)
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
