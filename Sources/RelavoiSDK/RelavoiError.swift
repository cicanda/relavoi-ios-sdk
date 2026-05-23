import Foundation

/// The single error type exposed by the SDK.
public enum RelavoiError: Error {
    /// `Relavoi.shared` was accessed without calling `initialize`.
    case notInitialized
    /// 401 from the API, or any auth misconfiguration.
    case unauthorized(detail: String)
    /// Transport failure (URLSession threw).
    case network(Error)
    /// Non-2xx response. `body` is the raw response body, trimmed for safety.
    case api(statusCode: Int, body: String?)
    /// Caller passed an invalid argument (e.g. malformed E.164 phone).
    case validation(detail: String)
    /// 429 from the API. `retryAfterSeconds` parsed from `Retry-After` when present.
    case rateLimited(retryAfterSeconds: TimeInterval?)
    /// Catch-all for unexpected SDK state.
    case unexpected(String)
}

extension RelavoiError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Relavoi SDK is not initialized. Call Relavoi.initialize(...) first."
        case .unauthorized(let detail):
            return "Unauthorized: \(detail)"
        case .network(let err):
            return "Network error: \(err.localizedDescription)"
        case .api(let status, let body):
            if let body = body, !body.isEmpty {
                return "API error (\(status)): \(body)"
            }
            return "API error (\(status))"
        case .validation(let detail):
            return "Validation error: \(detail)"
        case .rateLimited(let retry):
            if let r = retry {
                return "Rate limited. Retry after \(Int(r))s."
            }
            return "Rate limited."
        case .unexpected(let msg):
            return "Unexpected error: \(msg)"
        }
    }
}
