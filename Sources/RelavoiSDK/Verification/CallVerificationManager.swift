import Foundation

/// Surface for the "Revolut-style" call verification flow.
///
/// On iOS this combines a backend check (`GET /v1/sessions/verify`) with a `CXCallObserver` that
/// tracks whether the device currently has an active call.
public protocol CallVerificationManager {

    /// Ask the backend whether the currently-active call is a known Relavoi-routed session.
    func verify(userPhone: String) async throws -> VerificationResult

    /// Whether the OS reports an active phone call right now (CXCallObserver).
    var isCallActive: Bool { get }
}
