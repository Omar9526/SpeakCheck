import CryptoKit
import Foundation
import Security

/// Одноразовый nonce для «Входа через Apple»: Apple кладёт его SHA-256 в identity token,
/// а сервер сверяет с исходным значением. Перехваченный токен без nonce бесполезен.
enum AppleNonce {
    static func make(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        precondition(status == errSecSuccess, "Нет источника случайных чисел")
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
