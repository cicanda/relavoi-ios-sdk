import Foundation

/// Tiny manager for APNs device-token registration.
///
/// The push surface is intentionally not a protocol — there's only one implementation and it has
/// only two verbs.
public final class PushTokenManager {

    private let api: APIClient

    /// Dedupe cache of `(userPhoneHash, tokenHex)` pairs that have already been registered this
    /// process lifetime. Avoids hammering the backend on app foreground.
    private var registered: Set<String> = []
    private let dedupeQueue = DispatchQueue(label: "com.relavoi.sdk.push-dedupe")

    internal init(api: APIClient) {
        self.api = api
    }

    /// Register a device token for the given user phone.
    public func registerToken(
        userPhone: String,
        deviceToken: Data,
        appBundleId: String? = nil
    ) async throws {
        try PhoneUtils.requireValidE164(userPhone, fieldName: "userPhone")
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        let key = PhoneUtils.hashClientSide(userPhone) + ":" + hex
        if dedupeQueue.sync(execute: { registered.contains(key) }) {
            Logger.debug("push token already registered (dedupe hit)")
            return
        }

        struct Body: Encodable {
            let userPhone: String
            let token: String
            let platform: String
            let appBundleId: String?
        }
        let body = Body(
            userPhone: userPhone,
            token: hex,
            platform: "ios",
            appBundleId: appBundleId
        )
        let _: EmptyResponse = try await api.post("/devices/token", body: body)
        dedupeQueue.sync { registered.insert(key) }
    }

    /// Deactivate a token (e.g. on logout).
    public func deactivateToken(deviceToken: Data) async throws {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        // Backend reads the token from the DELETE request body: { "token": "..." }.
        struct Body: Encodable { let token: String }
        let _: EmptyResponse = try await api.delete("/devices/token", body: Body(token: hex))
        dedupeQueue.sync {
            registered = registered.filter { !$0.hasSuffix(":" + hex) }
        }
    }
}
