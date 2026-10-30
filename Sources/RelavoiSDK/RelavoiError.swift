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
    /// Caller passed an invalid argument (e.g. a field that is not number-shaped).
    case validation(detail: String)
    /// The API refused a phone number because Relavoi does not currently connect
    /// numbers of that kind. Today that means anything other than a Nigerian
    /// mobile number.
    ///
    /// This is a server decision, not a client one: the supported countries live
    /// in the platform's countries table and can change without a new SDK
    /// release, so do not try to pre-empt it with a local check. `detail` never
    /// contains the number that was refused.
    case numberNotSupported(detail: String)
    /// The API refused the session because the two numbers are not in the same
    /// country. Cross-border masking is a separate product and is not enabled.
    /// `detail` never contains either number.
    case crossBorderNotSupported(detail: String)
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
        case .numberNotSupported(let detail):
            return detail
        case .crossBorderNotSupported(let detail):
            return detail
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
