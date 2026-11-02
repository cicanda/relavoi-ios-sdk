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
    ///
    /// - Note: `recordingEnabled` and `consentPrompt` were removed in 0.3.0.
    ///   Recording is not available: the API refuses `recordingEnabled: true`
    ///   with `feature-not-available`, so the parameters configured nothing.
    ///   Both fields are still returned on ``Session``, because the API still
    ///   returns them.
    /// - Note: named `createSession`, not `create`, on purpose. See the
    ///   extension below: a protocol extension cannot safely provide default
    ///   arguments for a requirement it shares argument labels with.
    func createSession(
        agentPhone: String,
        customerPhone: String,
        metadata: [String: String]?,
        gracePeriodMinutes: Int,
        directionMode: DirectionMode
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
    ///
    /// - Note: named `listSessions` for the same reason as ``createSession``.
    func listSessions(
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

/// Default-parameter conveniences, so a caller writes `create(agentPhone:customerPhone:)`
/// and `list()`.
///
/// The requirements above are deliberately named `createSession` and
/// `listSessions` rather than `create` and `list`. In Swift, a protocol
/// extension method that shares its name and argument labels with a
/// requirement does not satisfy that requirement: it is a separate overload.
/// A call inside the extension body then resolves to the extension itself, and
/// the method calls itself until the stack runs out.
///
/// That is not hypothetical. It shipped. In 0.3.0 and 0.3.1 both of these
/// methods were declared here with the requirements' own labels and forwarded
/// to themselves, so `create(agentPhone:customerPhone:)` and `list()` crashed
/// the process instead of making a request, and the sample app in this
/// repository crashed on its first button. Distinct names make the mistake
/// impossible to repeat rather than merely absent: there is no overload for
/// the forwarding call below to resolve to except the requirement.
public extension SessionManager {
    func create(
        agentPhone: String,
        customerPhone: String,
        metadata: [String: String]? = nil,
        gracePeriodMinutes: Int = 15,
        directionMode: DirectionMode = .bidirectional
    ) async throws -> Session {
        try await createSession(
            agentPhone: agentPhone,
            customerPhone: customerPhone,
            metadata: metadata,
            gracePeriodMinutes: gracePeriodMinutes,
            directionMode: directionMode
        )
    }

    func list(
        state: SessionState? = nil,
        limit: Int = 20,
        after: String? = nil
    ) async throws -> SessionListResponse {
        try await listSessions(state: state, limit: limit, after: after)
    }
}
