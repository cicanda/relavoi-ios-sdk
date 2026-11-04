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

    func delete<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await send(method: "DELETE", path: path, body: body)
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

        // Path only, never the query string. /sessions/verify carries the
        // subscriber's number as a query parameter, so logging the full path
        // wrote a plaintext phone number into the unified log for anyone who
        // turned SDK logging on.
        Logger.network("\(method) \(APIClient.pathForLog(path))")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw RelavoiError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw RelavoiError.unexpected("Non-HTTP response on \(APIClient.pathForLog(path))")
        }

        // 401 → invalidate + retry once.
        if http.statusCode == 401 && !isRetry && !isAuthPath {
            await authManager.invalidate()
            return try await send(method: method, path: path, body: body, isRetry: true)
        }

        if http.statusCode == 401 {
            throw RelavoiError.unauthorized(detail: APIClient.problem(from: data)?.detail ?? "unauthorized")
        }

        // Before the 429 branch, because the number quota used to be answered
        // with a 429 and is now a 409. Matching the slug first means this SDK
        // reads either one correctly, so it cannot mistake a quota refusal for
        // a rate limit during a deploy, or if the status is ever moved again.
        if let slug = APIClient.problem(from: data)?.slug, slug == "number-quota-reached" {
            throw APIClient.error(status: http.statusCode, data: data)
        }

        if http.statusCode == 429 {
            let raw = http.value(forHTTPHeaderField: "Retry-After")
                ?? http.value(forHTTPHeaderField: "retry-after")
            let retry = raw.flatMap(TimeInterval.init)
            throw RelavoiError.rateLimited(retryAfterSeconds: retry)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw APIClient.error(status: http.statusCode, data: data)
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

    /// The backend serializes dates with fractional seconds (e.g.
    /// "2026-07-13T14:45:49.740Z"). `.iso8601` rejects the fractional part, so
    /// use a strategy that accepts dates with OR without fractional seconds.
    static let dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return .custom { decoder in
            let container = try decoder.singleValueContainer()
            let s = try container.decode(String.self)
            if let d = withFraction.date(from: s) ?? plain.date(from: s) { return d }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date format: \(s)"
            )
        }
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = APIClient.dateDecodingStrategy
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.keyEncodingStrategy = .useDefaultKeys
        return e
    }()

    // MARK: - Error mapping

    /// The two fields of an RFC 7807 problem document that the SDK reads.
    struct Problem {
        /// Last path segment of the `type` URL, e.g. `number-not-supported`.
        let slug: String?
        let detail: String?
    }

    /// Parse a problem document, or return nil if the body is not one.
    ///
    /// Only `type` and `detail` are read. The raw body is never surfaced in an
    /// error, which is deliberate rather than tidy: an error message ends up in
    /// a crash reporter, so what goes into it is limited to the fields whose
    /// contents we control. An error page from something in front of the API
    /// commonly echoes the request URI, and /sessions/verify carries a
    /// subscriber's number in its query string.
    static func problem(from data: Data) -> Problem? {
        guard !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let type = obj["type"] as? String
        let detail = obj["detail"] as? String
        let slug = type.flatMap { $0.split(separator: "/").last.map(String.init) }
        if slug == nil && detail == nil { return nil }
        return Problem(slug: slug, detail: detail)
    }

    /// Map a non-2xx response to a typed error.
    ///
    /// The slug is matched rather than the whole `type` URL so the error
    /// identity does not depend on the hostname, which differs by environment.
    static func error(status: Int, data: Data) -> RelavoiError {
        let parsed = problem(from: data)
        let detail = parsed?.detail

        // Matched on the slug alone, before any status check. The quota
        // refusal was a 429 and is now a 409, and it must not be read as a
        // rate limit under either: a rate limit says wait, and this one does
        // not clear by waiting.
        if parsed?.slug == "number-quota-reached" {
            return .numberQuotaReached(
                detail: detail
                    ?? "This workspace is holding every proxy number its plan allows at once."
            )
        }

        if status == 400 || status == 422 {
            switch parsed?.slug {
            case "number-not-supported":
                return .numberNotSupported(detail: detail ?? "That phone number is not supported.")
            case "cross-border-not-supported":
                return .crossBorderNotSupported(
                    detail: detail ?? "Both numbers in a session must be from the same country."
                )
            default:
                return .validation(detail: detail ?? "validation failed")
            }
        }
        return .api(statusCode: status, body: detail)
    }

    /// A path with any query string removed, for logs and messages.
    static func pathForLog(_ path: String) -> String {
        path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? path
    }

    /// Sentinel type used for endpoints that take no body.
    private struct Empty: Encodable {}
}

/// Decode target for endpoints that return 204/empty body.
public struct EmptyResponse: Decodable {
    public init() {}
}
