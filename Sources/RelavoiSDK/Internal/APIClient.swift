import Foundation

/// Thin REST client used by all SDK subsystems.
///
/// URLSession is thread-safe, so this is a plain `final class` (not an actor).
/// Callers are responsible for choosing the correct method shape.
final class APIClient {

    private let baseURL: URL
    private let session: URLSession
    private let authManager: AuthManager
    private let enableLogging: Bool

    init(baseURL: URL, session: URLSession, authManager: AuthManager, enableLogging: Bool) {
        self.baseURL = baseURL
        self.session = session
        self.authManager = authManager
        self.enableLogging = enableLogging
    }

    // MARK: - Public verbs

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(method: "GET", path: path, body: Optional<Empty>.none)
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await send(method: "POST", path: path, body: body)
    }

    func delete<T: Decodable>(_ path: String) async throws -> T {
        try await send(method: "DELETE", path: path, body: Optional<Empty>.none)
    }

    func patch<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await send(method: "PATCH", path: path, body: body)
    }

    // Convenience: no-body POSTs (e.g. /sessions/{id}/end).
    func post<T: Decodable>(_ path: String) async throws -> T {
        try await send(method: "POST", path: path, body: Optional<Empty>.none)
    }

    // MARK: - Core

    private func send<T: Decodable, B: Encodable>(
        method: String,
        path: String,
        body: B?,
        isRetry: Bool = false
    ) async throws -> T {

        var req = URLRequest(url: resolve(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        // Skip auth header on the auth bootstrap path itself.
        let isAuthPath = path.hasPrefix("/auth/token") || path.hasPrefix("auth/token")
        if !isAuthPath {
            let token = try await authManager.getValidToken()
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try APIClient.encoder.encode(body)
        }

        Logger.network("\(method) \(path)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw RelavoiError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw RelavoiError.unexpected("Non-HTTP response on \(path)")
        }

        // 401 → invalidate + retry once.
        if http.statusCode == 401 && !isRetry && !isAuthPath {
            await authManager.invalidate()
            return try await send(method: method, path: path, body: body, isRetry: true)
        }

        if http.statusCode == 401 {
            let bodyStr = String(data: data, encoding: .utf8) ?? "unauthorized"
            throw RelavoiError.unauthorized(detail: bodyStr)
        }

        if http.statusCode == 429 {
            let raw = http.value(forHTTPHeaderField: "Retry-After")
                ?? http.value(forHTTPHeaderField: "retry-after")
            let retry = raw.flatMap(TimeInterval.init)
            throw RelavoiError.rateLimited(retryAfterSeconds: retry)
        }

        guard (200..<300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8)
            throw RelavoiError.api(statusCode: http.statusCode, body: bodyStr)
        }

        // Empty body but Decodable T == EmptyResponse? Support via the EmptyResponse sentinel.
        if data.isEmpty, let empty = EmptyResponse() as? T {
            return empty
        }

        do {
            return try APIClient.decoder.decode(T.self, from: data)
        } catch {
            throw RelavoiError.unexpected("Decoding \(T.self) failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func resolve(_ path: String) -> URL {
        // baseURL already ends in /v1 — caller paths like "/sessions" or "sessions" both work.
        // We split on "?" so query strings are preserved correctly (appendingPathComponent would
        // percent-encode "?" and "&").
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let parts = trimmed.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let pathPart = String(parts[0])
        let queryPart = parts.count > 1 ? String(parts[1]) : nil

        let base = baseURL.appendingPathComponent(pathPart)
        guard let query = queryPart, !query.isEmpty else { return base }

        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)
        comps?.percentEncodedQuery = query
        return comps?.url ?? base
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.keyEncodingStrategy = .useDefaultKeys
        return e
    }()

    /// Sentinel type used for endpoints that take no body.
    private struct Empty: Encodable {}
}

/// Decode target for endpoints that return 204/empty body.
public struct EmptyResponse: Decodable {
    public init() {}
}
