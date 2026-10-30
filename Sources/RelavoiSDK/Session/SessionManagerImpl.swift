import Foundation
#if canImport(UIKit)
import UIKit
#endif

final class SessionManagerImpl: SessionManager {

    private let api: APIClient

    /// In-memory cache, protected by a serial queue. Cleared on `end()`.
    private var cache: [String: Session] = [:]
    private let cacheQueue = DispatchQueue(label: "com.relavoi.sdk.session-cache")

    init(api: APIClient) {
        self.api = api
    }

    // MARK: - SessionManager

    func create(
        agentPhone: String,
        customerPhone: String,
        metadata: [String: String]?,
        gracePeriodMinutes: Int,
        directionMode: DirectionMode,
        recordingEnabled: Bool,
        consentPrompt: ConsentPrompt
    ) async throws -> Session {
        let agent = try PhoneUtils.requireNumberShaped(agentPhone, fieldName: "agentPhone")
        let customer = try PhoneUtils.requireNumberShaped(customerPhone, fieldName: "customerPhone")

        let body = CreateSessionRequest(
            agentPhone: agentPhone,
            customerPhone: customerPhone,
            metadata: metadata,
            gracePeriodMinutes: gracePeriodMinutes,
            directionMode: directionMode.rawValue,
            recordingEnabled: recordingEnabled,
            consentPrompt: consentPrompt.rawValue
        )

        // No part of either number goes in here. The last four digits are still
        // part of a number, and this line reaches the unified log.
        Logger.info("create session")

        let session: Session = try await api.post("/sessions", body: body)
        store(session)
        return session
    }

    func get(_ id: String) async throws -> Session {
        if let cached = read(id), cached.expiresAt > Date() {
            return cached
        }
        let session: Session = try await api.get("/sessions/\(id)")
        store(session)
        return session
    }

    func swapTarget(_ id: String, customerPhone: String) async throws -> Session {
        let session: Session = try await api.patch(
            "/sessions/\(id)/target",
            body: SwapTargetRequest(customerPhone: customerPhone)
        )
        // The cached copy still names the old target.
        store(session)
        return session
    }

    func end(_ id: String) async throws -> Session {
        let session: Session = try await api.post("/sessions/\(id)/end")
        remove(id)
        return session
    }

    func list(
        state: SessionState?,
        limit: Int,
        after: String?
    ) async throws -> SessionListResponse {
        var query: [String] = ["limit=\(limit)"]
        if let s = state { query.append("state=\(s.rawValue)") }
        if let a = after, let escaped = a.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            query.append("after=\(escaped)")
        }
        let path = "/sessions?" + query.joined(separator: "&")
        return try await api.get(path)
    }

    func verify(userPhone: String) async throws -> VerificationResult {
        let canonical = try PhoneUtils.requireNumberShaped(userPhone, fieldName: "userPhone")
        // Send the number as the caller gave it, minus separators; the backend
        // normalises it and hashes it server-side with a per-tenant salt, so a
        // client-side hash could never match.
        //
        // This number is in the query string, which is why APIClient logs the
        // path without it.
        return try await api.get("/sessions/verify?userPhone=\(PhoneUtils.queryEncode(canonical))")
    }

    @MainActor
    func initiateCall(sessionId: String) async throws {
        let session: Session
        if let cached = read(sessionId), cached.expiresAt > Date() {
            session = cached
        } else {
            session = try await get(sessionId)
        }

        #if canImport(UIKit)
        let digitsOnly = session.proxyNumber.filter { "+0123456789".contains($0) }
        guard let url = URL(string: "tel:\(digitsOnly)") else {
            throw RelavoiError.unexpected("Could not build tel: URL for proxy number")
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            UIApplication.shared.open(url, options: [:]) { _ in
                cont.resume()
            }
        }
        #else
        throw RelavoiError.unexpected("UIApplication not available on this platform")
        #endif
    }

    // MARK: - Cache helpers

    private func store(_ session: Session) {
        cacheQueue.sync { cache[session.id] = session }
    }

    private func read(_ id: String) -> Session? {
        cacheQueue.sync { cache[id] }
    }

    private func remove(_ id: String) {
        cacheQueue.sync { _ = cache.removeValue(forKey: id) }
    }
}
