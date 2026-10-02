import Foundation

/// Public surface for managing masking sessions.
///
/// Implementations are obtained via ``Relavoi/sessions``.
public protocol SessionManager {

    /// Create a new masking session.
    ///
    /// - Parameters:
    ///   - agentPhone: E.164 (e.g. `+2348012345678`)
    ///   - customerPhone: E.164
    ///   - metadata: Free-form key/value pairs persisted with the session (e.g. order id).
    ///   - gracePeriodMinutes: How long after `end()` the session stays callable. Default `15`.
    ///   - directionMode: Who can call whom. Default `.bidirectional`.
    ///   - recordingEnabled: Whether calls are recorded. Default `false`.
    ///   - consentPrompt: Recording consent flow. Default `.none`.
    func create(
        agentPhone: String,
        customerPhone: String,
        metadata: [String: String]?,
        gracePeriodMinutes: Int,
        directionMode: DirectionMode,
        recordingEnabled: Bool,
        consentPrompt: ConsentPrompt
    ) async throws -> Session

    /// Fetch a session by id. Uses an in-process cache when available.
    func get(_ id: String) async throws -> Session

    /// Swap the customer (party B) on an active session, keeping the proxy number.
    ///
    /// Use this for sequential calls rather than one session per recipient: ten
    /// sessions means ten numbers and ten cooldowns, which exhausts a small pool
    /// partway through a round. The agent keeps dialling the same proxy and each
    /// call connects to whoever the current target is.
    ///
    /// The previous customer can no longer reach the proxy afterwards. Swapping
    /// to the current target is a no-op. Throws if `customerPhone` is not E.164,
    /// is the agent's own number, or already participates in another live
    /// session on the same proxy.
    func swapTarget(_ id: String, customerPhone: String) async throws -> Session

    /// End a session. Returns the updated server state (typically `.gracePeriod`).
    func end(_ id: String) async throws -> Session

    /// List sessions for the current tenant. Cursor-based via `after`.
    func list(
        state: SessionState?,
        limit: Int,
        after: String?
    ) async throws -> SessionListResponse

    /// Call-verification check for the currently-active phone call.
    func verify(userPhone: String) async throws -> VerificationResult

    /// Open the system dialer pointed at the session's proxy number.
    ///
    /// - Important: Must be invoked on the main actor (UIKit requirement).
    /// - Throws: `RelavoiError.unexpected` on platforms without UIKit.
    @MainActor
    func initiateCall(sessionId: String) async throws
}

// Default-parameter convenience extension so callers can omit common fields.
public extension SessionManager {
    func create(
        agentPhone: String,
        customerPhone: String,
        metadata: [String: String]? = nil,
        gracePeriodMinutes: Int = 15,
        directionMode: DirectionMode = .bidirectional,
        recordingEnabled: Bool = false,
        consentPrompt: ConsentPrompt = .none
    ) async throws -> Session {
        try await create(
            agentPhone: agentPhone,
            customerPhone: customerPhone,
            metadata: metadata,
            gracePeriodMinutes: gracePeriodMinutes,
            directionMode: directionMode,
            recordingEnabled: recordingEnabled,
            consentPrompt: consentPrompt
        )
    }

    func list(
        state: SessionState? = nil,
        limit: Int = 20,
        after: String? = nil
    ) async throws -> SessionListResponse {
        try await list(state: state, limit: limit, after: after)
    }
}
