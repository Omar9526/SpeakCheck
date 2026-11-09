import Foundation
import Security

/// Токены сессии в Keychain (только для этого устройства, после первой разблокировки).
enum TokenStore {
    private static let service = "kg.speakcheck.app.tokens"

    // Кеш в памяти: токен доступен в сессии, даже если Keychain временно недоступен.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: String] = [:]

    static var accessToken: String? { value("access") }
    static var refreshToken: String? { value("refresh") }

    static func save(access: String, refresh: String?) {
        set("access", access)
        if let refresh { set("refresh", refresh) }
    }

    private static func value(_ account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let v = cache[account] { return v }
        let v = read(account)
        cache[account] = v
        return v
    }

    private static func set(_ account: String, _ value: String) {
        lock.lock(); cache[account] = value; lock.unlock()
        write(account, value)
    }

    static func clear() {
        lock.lock(); cache = [:]; lock.unlock()
        for account in ["access", "refresh"] {
            SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary)
        }
    }

    private static func read(_ account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
            kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ account: String, _ value: String) {
        let base: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData] = Data(value.utf8)
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}
