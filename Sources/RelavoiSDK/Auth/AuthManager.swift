import Foundation

/// Manages the short-lived JWT used for all API calls.
///
/// - Note: AuthManager uses `URLSession.shared` directly for its `/auth/token` call rather than
///   accepting an injected session. The injectable `URLSession` on ``APIClient`` is for the rest of
///   the SDK. Tests can intercept `URLSession.shared` via `URLProtocol.registerClass(...)`.
actor AuthManager {

    /// Where tokens come from.
    ///
    /// `.provider` is the one to use in a shipped app: the secret stays on
    /// your backend. `.credentials` is the original form, kept working for
    /// local development and for integrations that have not moved yet.
    enum Source {
        case credentials(apiKey: String, apiSecret: String)
        case provider(RelavoiTokenProvider)
    }

    // MARK: - Stored

    private let source: Source
    private let tenantId: String
    private let baseURL: URL
    private let tokenStore: TokenStore

    /// In-memory cache. Refreshed when within `refreshLeadTime` of expiry.
    private var cached: (token: String, expiresAt: Date)?

    /// Refresh tokens this many seconds before they actually expire to avoid clock-edge 401s.
    private let refreshLeadTime: TimeInterval = 60

    /// In-flight refresh task so concurrent callers don't all hit `/auth/token`.
    private var inFlightRefresh: Task<String, Error>?

    init(source: Source, tenantId: String, baseURL: URL, tokenStore: TokenStore) {
        self.source = source
        self.tenantId = tenantId
        self.baseURL = baseURL
        self.tokenStore = tokenStore

        // Hydrate from the Keychain, but only for the credentials path.
        //
        // A provider token is already short-lived and the provider can always
        // produce another, so persisting one buys nothing and costs something:
        // a token that outlives a sign-out in your app would keep working
        // until it expired.
        if case .credentials = source, let persisted = tokenStore.load() {
            self.cached = (persisted.0, persisted.1)
        }
    }

    /// Kept for source compatibility with the deprecated initializer.
    init(apiKey: String, apiSecret: String, tenantId: String, baseURL: URL, tokenStore: TokenStore) {
        self.init(
            source: .credentials(apiKey: apiKey, apiSecret: apiSecret),
            tenantId: tenantId,
            baseURL: baseURL,
            tokenStore: tokenStore
        )
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
        switch source {
        case .provider(let provide):
            let token = try await provide()
            guard !token.accessToken.isEmpty else {
                throw RelavoiError.unexpected("Token provider returned an empty accessToken")
            }
            let expiresAt = Date().addingTimeInterval(TimeInterval(max(token.expiresIn, 0)))
            cached = (token.accessToken, expiresAt)
            // Deliberately not persisted. See init.
            return token.accessToken
        case .credentials(let apiKey, let apiSecret):
            return try await performCredentialsRefresh(apiKey: apiKey, apiSecret: apiSecret)
        }
    }

    private func performCredentialsRefresh(apiKey: String, apiSecret: String) async throws -> String {
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
