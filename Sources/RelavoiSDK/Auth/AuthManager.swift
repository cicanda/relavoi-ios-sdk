import Foundation

/// Manages the short-lived JWT used for all API calls.
///
/// - Note: AuthManager uses `URLSession.shared` directly for its `/auth/token` call rather than
///   accepting an injected session. The injectable `URLSession` on ``APIClient`` is for the rest of
///   the SDK. Tests can intercept `URLSession.shared` via `URLProtocol.registerClass(...)`.
actor AuthManager {

    // MARK: - Stored

    private let apiKey: String
    private let apiSecret: String
    private let tenantId: String
    private let baseURL: URL
    private let tokenStore: TokenStore

    /// In-memory cache. Refreshed when within `refreshLeadTime` of expiry.
    private var cached: (token: String, expiresAt: Date)?

    /// Refresh tokens this many seconds before they actually expire to avoid clock-edge 401s.
    private let refreshLeadTime: TimeInterval = 60

    /// In-flight refresh task so concurrent callers don't all hit `/auth/token`.
    private var inFlightRefresh: Task<String, Error>?

    init(apiKey: String, apiSecret: String, tenantId: String, baseURL: URL, tokenStore: TokenStore) {
        self.apiKey = apiKey
        self.apiSecret = apiSecret
        self.tenantId = tenantId
        self.baseURL = baseURL
        self.tokenStore = tokenStore

        // Hydrate from Keychain on first init.
        if let persisted = tokenStore.load() {
            self.cached = (persisted.0, persisted.1)
        }
    }

    // MARK: - API

    /// Returns a valid token, refreshing if needed.
    func getValidToken() async throws -> String {
        if let c = cached, c.expiresAt.timeIntervalSinceNow > refreshLeadTime {
            return c.token
        }
        return try await refreshToken()
    }

    /// Force a token refresh. Concurrent calls share one in-flight task.
    @discardableResult
    func refreshToken() async throws -> String {
        if let task = inFlightRefresh {
            return try await task.value
        }
        let task = Task<String, Error> { [self] in
            try await self.performRefresh()
        }
        inFlightRefresh = task
        defer { inFlightRefresh = nil }
        return try await task.value
    }

    /// Drops cached token and clears Keychain.
    func invalidate() async {
        cached = nil
        tokenStore.clear()
    }

    // MARK: - Internal

    private func performRefresh() async throws -> String {
        let url = baseURL.appendingPathComponent("auth/token")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        struct Body: Encodable { let apiKey: String; let apiSecret: String }
        req.httpBody = try JSONEncoder().encode(Body(apiKey: apiKey, apiSecret: apiSecret))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw RelavoiError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw RelavoiError.unexpected("Non-HTTP response on /auth/token")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            if http.statusCode == 401 {
                throw RelavoiError.unauthorized(detail: body ?? "invalid credentials")
            }
            throw RelavoiError.api(statusCode: http.statusCode, body: body)
        }

        struct TokenResponse: Decodable { let accessToken: String; let expiresIn: Int }
        let decoded: TokenResponse
        do {
            decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw RelavoiError.unexpected("Invalid /auth/token payload: \(error.localizedDescription)")
        }

        let expiresAt = Date().addingTimeInterval(TimeInterval(decoded.expiresIn))
        cached = (decoded.accessToken, expiresAt)
        tokenStore.save(token: decoded.accessToken, expiresAt: expiresAt)
        return decoded.accessToken
    }
}
