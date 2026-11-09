import Foundation

/// Отправка настроек профиля на сервер (PATCH /me, сервер дополняет, а не заменяет настройки).
/// Без сервера (нет SCAPIBaseURL) и при ошибке сети — тихо пропускается: настройки остаются на устройстве.
enum ProfileSync {
    struct Preferences: Encodable, Sendable {
        var keepAudio: Bool?
        var voiceConsent: Bool?
        var explanationLanguage: String?
        var goal: String?
        var firstScoreSeconds: Int?
    }

    private struct Body: Encodable, Sendable { let preferences: Preferences }

    static func push(_ preferences: Preferences) {
        guard APIClient.baseURL != nil else { return }
        Task.detached {
            let _: EmptyResponse? = try? await APIClient.shared.patch("me", json: Body(preferences: preferences))
        }
    }
}
