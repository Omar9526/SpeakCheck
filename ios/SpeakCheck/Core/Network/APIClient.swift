import Foundation

/// HTTP-клиент backend `/api/v1`. Ключи Azure/DeepSeek на устройстве не хранятся —
/// только access/refresh токены пользователя в Keychain.
actor APIClient {
    struct ServerError: Error, Decodable, Sendable {
        let code: String
        let message: String
        let requestID: String?

        enum CodingKeys: String, CodingKey {
            case code, message
            case requestID = "request_id"
        }
    }

    enum ClientError: Error {
        case notConfigured
        case unauthorized
        case server(ServerError, status: Int)
        case invalidResponse
    }

    static let baseURL: URL? = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SCAPIBaseURL") as? String,
              !raw.isEmpty, let url = URL(string: raw) else { return nil }
        #if !DEBUG
        // В релизе — только HTTPS: токены и записи голоса не должны идти открытым текстом.
        guard url.scheme == "https" else { return nil }
        #endif
        return url
    }()

    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var refreshTask: Task<Void, Error>?

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = APIClient.isoFractional.date(from: raw) ?? APIClient.iso.date(from: raw) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(raw)"))
        }
        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let iso = ISO8601DateFormatter()

    // MARK: Public API

    func get<T: Decodable & Sendable>(_ path: String) async throws -> T {
        try await send(path, method: "GET", body: nil, contentType: nil)
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, json body: B) async throws -> T {
        try await send(path, method: "POST", body: try encoder.encode(body), contentType: "application/json")
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, json body: B) async throws -> T {
        try await send(path, method: "PATCH", body: try encoder.encode(body), contentType: "application/json")
    }

    func delete(_ path: String) async throws {
        let _: EmptyResponse = try await send(path, method: "DELETE", body: nil, contentType: nil)
    }

    /// multipart/form-data с одним файлом.
    func upload<T: Decodable & Sendable>(_ path: String, fileURL: URL, field: String, mimeType: String,
                                         headers: [String: String]) async throws -> T {
        let boundary = "sc-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(field)\"; filename=\"\(fileURL.lastPathComponent)\"\r\nContent-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: fileURL))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return try await send(path, method: "POST", body: body, contentType: "multipart/form-data; boundary=\(boundary)",
                              extraHeaders: headers)
    }

    // MARK: Auth

    func authenticateAsGuestIfNeeded() async throws {
        if TokenStore.accessToken != nil { return }
        let tokens: AuthResponse = try await send("auth/guest", method: "POST",
                                                  body: try encoder.encode(["locale": "ru"]),
                                                  contentType: "application/json", authorized: false)
        TokenStore.save(access: tokens.access, refresh: tokens.refresh)
    }

    func signInWithApple(identityToken: String, nonce: String) async throws {
        struct Body: Encodable, Sendable { let identityToken: String; let nonce: String; let linkGuest: Bool }
        // Если есть гостевой токен — сервер перенесёт данные гостя в Apple-аккаунт.
        let tokens: AuthResponse = try await send("auth/apple", method: "POST",
                                                  body: try encoder.encode(Body(identityToken: identityToken, nonce: nonce, linkGuest: true)),
                                                  contentType: "application/json", authorized: TokenStore.accessToken != nil)
        TokenStore.save(access: tokens.access, refresh: tokens.refresh)
    }

    /// Выход: сервер отзывает refresh-токен, затем токены стираются с устройства.
    func logout() async {
        if let refresh = TokenStore.refreshToken, TokenStore.accessToken != nil {
            let _: EmptyResponse? = try? await send("auth/logout", method: "POST",
                                                    body: try? encoder.encode(["refresh": refresh]),
                                                    contentType: "application/json")
        }
        TokenStore.clear()
    }

    // MARK: Core

    private func send<T: Decodable & Sendable>(_ path: String, method: String, body: Data?, contentType: String?,
                                               extraHeaders: [String: String] = [:], authorized: Bool = true,
                                               retryOnAuth: Bool = true) async throws -> T {
        guard let base = Self.baseURL else { throw ClientError.notConfigured }
        if authorized { try await authenticateAsGuestIfNeeded() }

        var request = URLRequest(url: base.appendingPathComponent("api/v1/" + path))
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(UUID().uuidString.replacingOccurrences(of: "-", with: ""), forHTTPHeaderField: "X-Request-ID")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if authorized, let token = TokenStore.accessToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        extraHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }

        if http.statusCode == 401, authorized, retryOnAuth {
            try await refreshTokens()
            return try await send(path, method: method, body: body, contentType: contentType,
                                  extraHeaders: extraHeaders, authorized: authorized, retryOnAuth: false)
        }
        guard (200..<300).contains(http.statusCode) else {
            if let error = try? decoder.decode(ServerError.self, from: data) {
                throw ClientError.server(error, status: http.statusCode)
            }
            throw ClientError.invalidResponse
        }
        if T.self == EmptyResponse.self || data.isEmpty { return EmptyResponse() as! T }
        return try decoder.decode(T.self, from: data)
    }

    private func refreshTokens() async throws {
        if let refreshTask { return try await refreshTask.value }
        let task = Task<Void, Error> {
            defer { self.refreshTask = nil }
            guard let refresh = TokenStore.refreshToken else {
                TokenStore.clear()
                try await self.authenticateAsGuestIfNeeded()
                return
            }
            do {
                let tokens: AuthResponse = try await self.send("auth/refresh", method: "POST",
                                                               body: try self.encoder.encode(["refresh": refresh]),
                                                               contentType: "application/json", authorized: false)
                TokenStore.save(access: tokens.access, refresh: tokens.refresh ?? refresh)
            } catch {
                // Refresh истёк: новый гостевой аккаунт (локальные данные остаются на устройстве).
                TokenStore.clear()
                try await self.authenticateAsGuestIfNeeded()
            }
        }
        refreshTask = task
        try await task.value
    }
}

struct EmptyResponse: Decodable, Sendable {}

struct AuthResponse: Decodable, Sendable {
    let access: String
    let refresh: String?
}
