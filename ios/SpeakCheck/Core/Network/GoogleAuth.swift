import GoogleSignIn
import UIKit

/// Вход через Google: SDK показывает окно Google, сервер проверяет ID token (POST /auth/google).
/// Как и у Apple, в токен уходит SHA-256 от случайного nonce, а серверу — сам nonce.
@MainActor
enum GoogleAuth {
    enum Failure: Error { case notConfigured, noPresenter, noToken }

    /// Кнопка показывается, только если в сборке задан iOS Client ID.
    static var isConfigured: Bool {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else { return false }
        return id.hasSuffix(".apps.googleusercontent.com")
    }

    static func signIn() async throws {
        guard isConfigured else { throw Failure.notConfigured }
        guard let presenter = topViewController() else { throw Failure.noPresenter }
        let nonce = AppleNonce.make()
        let (token, profile): (String, AccountProfile) = try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: nil, additionalScopes: nil,
                                            nonce: AppleNonce.sha256(nonce)) { result, error in
                guard let user = result?.user, let token = user.idToken?.tokenString else {
                    return continuation.resume(throwing: error ?? Failure.noToken)
                }
                let profile = AccountProfile(name: user.profile?.name, email: user.profile?.email,
                                             avatarURL: user.profile?.imageURL(withDimension: 120)?.absoluteString)
                continuation.resume(returning: (token, profile))
            }
        }
        try await APIClient.shared.signInWithGoogle(idToken: token, nonce: nonce)
        AccountProfile.current = profile
    }

    static func isCancellation(_ error: Error) -> Bool {
        (error as NSError).domain == kGIDSignInErrorDomain && (error as NSError).code == GIDSignInError.canceled.rawValue
    }

    static func handle(_ url: URL) -> Bool { GIDSignIn.sharedInstance.handle(url) }

    static func signOut() { GIDSignIn.sharedInstance.signOut() }

    /// Профиль из сохранённого входа Google (для тех, кто вошёл до появления имени в профиле).
    static func restoreProfile() async -> AccountProfile? {
        guard isConfigured else { return nil }
        return await withCheckedContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, _ in
                continuation.resume(returning: user.map {
                    AccountProfile(name: $0.profile?.name, email: $0.profile?.email,
                                   avatarURL: $0.profile?.imageURL(withDimension: 120)?.absoluteString)
                })
            }
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// Чем вошёл пользователь — для профиля. nil — гостевой режим.
enum SignInProvider: String {
    case apple, google

    private static let key = "sc.signInProvider"

    static var current: SignInProvider? {
        get {
            if let raw = UserDefaults.standard.string(forKey: key) { return SignInProvider(rawValue: raw) }
            return UserDefaults.standard.bool(forKey: "sc.appleSignedIn") ? .apple : nil  // старые установки
        }
        set {
            UserDefaults.standard.set(newValue?.rawValue, forKey: key)
            UserDefaults.standard.removeObject(forKey: "sc.appleSignedIn")
            if newValue == nil { AccountProfile.current = nil }
        }
    }

    var title: String { self == .apple ? "Вход через Apple" : "Вход через Google" }
    var shortName: String { self == .apple ? "Apple" : "Google" }
}

/// Имя, email и фото из аккаунта Apple/Google для шапки профиля. Сервер получает имя и email
/// из проверенного токена (фото — нет).
struct AccountProfile: Codable, Sendable {
    var name: String?
    var email: String?
    var avatarURL: String?

    private static let key = "sc.accountProfile"

    static var current: AccountProfile? {
        get {
            guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(AccountProfile.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    var initials: String {
        let parts = (name ?? "").split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}
