import Foundation
// CallKit IS importable on macOS, but CXCallObserver, CXCall and
// CXCallObserverDelegate are all `@available(macOS, unavailable)`, so
// `canImport(CallKit)` is true there and guards nothing. Gate on the platform.
#if os(iOS)
import CallKit
#endif

#if os(iOS)

/// Wraps `CXCallObserver` to track whether the device is currently on a call.
final class CallStateObserver: NSObject, CXCallObserverDelegate {

    private let observer = CXCallObserver()
    private(set) var isOnCall: Bool = false

    override init() {
        super.init()
        // Passing `nil` queue means delegate callbacks run on the main queue.
        observer.setDelegate(self, queue: nil)
    }

    func callObserver(_ observer: CXCallObserver, callChanged call: CXCall) {
        // A "call is in progress" if at least one tracked call has not ended.
        let active = observer.calls.contains { !$0.hasEnded }
        isOnCall = active
        // Fall back to the single-call signal if the calls list is empty for some reason.
        if observer.calls.isEmpty {
            isOnCall = !call.hasEnded
        }
    }
}

#else

/// Stub for platforms where CXCallObserver does not exist (macOS host builds,
/// Linux). `isCallActive` is therefore always false off iOS.
final class CallStateObserver: NSObject {
    private(set) var isOnCall: Bool = false
}

#endif

/// Default ``CallVerificationManager`` implementation. Lives here for compactness.
final class CallVerificationManagerImpl: CallVerificationManager {

    private let api: APIClient
    private let observer: CallStateObserver

    init(api: APIClient) {
        self.api = api
        self.observer = CallStateObserver()
    }

    func verify(userPhone: String) async throws -> VerificationResult {
        try PhoneUtils.requireNumberShaped(userPhone, fieldName: "userPhone")
        // Raw E.164 under `userPhone`; backend hashes server-side with per-tenant salt.
        return try await api.get("/sessions/verify?userPhone=\(PhoneUtils.queryEncode(userPhone))")
    }

    var isCallActive: Bool { observer.isOnCall }
}
