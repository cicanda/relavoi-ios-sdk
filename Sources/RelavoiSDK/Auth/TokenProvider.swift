import Foundation

/// A token your own backend minted, handed to the SDK.
///
/// The SDK caches it until shortly before `expiresIn` elapses and then asks
/// for another, so a provider that is cheap to call stays cheap.
public struct RelavoiToken: Sendable, Equatable {

    /// The `accessToken` from `POST /v1/auth/sdk-token`.
    public let accessToken: String

    /// Seconds from now, as returned by that endpoint.
    public let expiresIn: Int

    public init(accessToken: String, expiresIn: Int) {
        self.accessToken = accessToken
        self.expiresIn = expiresIn
    }
}

/// How the SDK asks your app for a token.
///
/// Your app calls your backend, which holds the API secret and calls
/// `POST /v1/auth/sdk-token`. The secret never reaches the handset, which is
/// the whole point: anything compiled into a published app can be read back
/// out of it.
///
/// ```swift
/// Relavoi.initialize(tenantId: "...") {
///     let token = try await MyBackend.relavoiToken()
///     return RelavoiToken(accessToken: token.accessToken, expiresIn: token.expiresIn)
/// }
/// ```
///
/// The SDK calls this on first use, shortly before the current token expires,
/// and once after a 401. If it throws, the error surfaces to the caller rather
/// than being retried in a loop: a failing provider usually means the user is
/// signed out of your app, and the right answer is to stop, not to hammer.
public typealias RelavoiTokenProvider = @Sendable () async throws -> RelavoiToken
