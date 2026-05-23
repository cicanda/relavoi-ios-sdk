import Foundation

/// Result of a call-verification check against `GET /v1/sessions/verify`.
///
/// `verified == true` means the SDK is confident this active call is from a Relavoi proxy number
/// matched to an active session — display a trusted/green banner. `verified == false` means the
/// call cannot be matched — display a warning/red banner.
public struct VerificationResult: Decodable, Equatable {
    public let verified: Bool
    public let context: String?
    public let sessionId: String?
    public let expiresAt: Date?

    public init(verified: Bool, context: String?, sessionId: String?, expiresAt: Date?) {
        self.verified = verified
        self.context = context
        self.sessionId = sessionId
        self.expiresAt = expiresAt
    }
}
