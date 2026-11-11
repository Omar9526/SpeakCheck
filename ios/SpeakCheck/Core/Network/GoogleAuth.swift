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
        let token: String = try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: nil, additionalScopes: nil,
                                            nonce: AppleNonce.sha256(nonce)) { result, error in
                if let token = result?.user.idToken?.tokenString { continuation.resume(returning: token) }
                else { continuation.resume(throwing: error ?? Failure.noToken) }
            }
        }
        try await APIClient.shared.signInWithGoogle(idToken: token, nonce: nonce)
    }

    static func isCancellation(_ error: Error) -> Bool {
        (error as NSError).domain == kGIDSignInErrorDomain && (error as NSError).code == GIDSignInError.canceled.rawValue
    }

    static func handle(_ url: URL) -> Bool { GIDSignIn.sharedInstance.handle(url) }

    static func signOut() { GIDSignIn.sharedInstance.signOut() }

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
        }
    }

    var title: String { self == .apple ? "Вход через Apple" : "Вход через Google" }
}
