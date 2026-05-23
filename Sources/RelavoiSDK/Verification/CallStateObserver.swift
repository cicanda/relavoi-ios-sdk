import Foundation
#if canImport(CallKit)
import CallKit
#endif

#if canImport(CallKit)

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

/// Stub for platforms without CallKit (e.g. swift build on a Linux host).
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
        try PhoneUtils.requireValidE164(userPhone, fieldName: "userPhone")
        let hash = PhoneUtils.hashClientSide(userPhone)
        return try await api.get("/sessions/verify?user_phone=\(hash)")
    }

    var isCallActive: Bool { observer.isOnCall }
}
