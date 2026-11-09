import XCTest
@testable import RelavoiSDK

final class SessionManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Fixtures

    private func makeAPI() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self] + (config.protocolClasses ?? [])
        let session = URLSession(configuration: config)
        let store = TokenStore(tenantId: "session-test-\(UUID().uuidString)")
        store.clear()
        let auth = AuthManager(
            apiKey: "sk_test",
            apiSecret: "secret",
            tenantId: "session-test",
            baseURL: URL(string: "https://api.relavoi.com/v1")!,
            tokenStore: store
        )
        return APIClient(
            baseURL: URL(string: "https://api.relavoi.com/v1")!,
            session: session,
            authManager: auth,
            enableLogging: false
        )
    }

    private func enqueueTokenRefresh() {
        MockURLProtocol.enqueue { _ in
            (200, ["Content-Type": "application/json"], Data(#"{"accessToken":"jwt","expiresIn":900}"#.utf8))
        }
    }

    private func sessionJSON(id: String = "sess-1") -> String {
        // Expiry far in the future so the cache check (expiresAt > now) passes.
        return """
        {
          "id": "\(id)",
          "tenantId": "tenant-x",
          "proxyNumber": "+2348099999999",
          "state": "ACTIVE",
          "directionMode": "BIDIRECTIONAL",
          "metadata": {"orderId": "ORD-1", "count": 3, "nested": {"a": 1}},
          "gracePeriodMinutes": 15,
          "maxDurationMinutes": 120,
          "recordingEnabled": false,
          "consentPrompt": "NONE",
          "expiresAt": "2999-01-01T00:00:00.000Z",
          "createdAt": "2026-05-22T10:00:00.000Z",
          "activatedAt": "2026-05-22T10:00:05.000Z",
          "endedAt": null,
          "expiredAt": null,
          "callCount": 0,
          "lastCallAt": null
        }
        """
    }

    // MARK: - Tests

    func testCreate_validInputs_returnsSession() async throws {
        let api = makeAPI()
        let mgr = SessionManagerImpl(api: api)

        enqueueTokenRefresh()
        MockURLProtocol.enqueue { _ in
            (200, ["Content-Type": "application/json"], Data(self.sessionJSON().utf8))
        }

        let s = try await mgr.create(
            agentPhone: "+2349000000001",
            customerPhone: "+2349000000002",
            metadata: ["orderId": "ORD-1"],
            gracePeriodMinutes: 15,
            directionMode: .bidirectional
        )

        XCTAssertEqual(s.id, "sess-1")
        XCTAssertEqual(s.state, .active)
        XCTAssertEqual(s.proxyNumber, "+2348099999999")
    }

    func testCreate_invalidPhone_throwsValidation() async {
        let api = makeAPI()
        let mgr = SessionManagerImpl(api: api)

        do {
            _ = try await mgr.create(
                agentPhone: "not-a-phone",
                customerPhone: "+2349000000002",
                metadata: nil,
                gracePeriodMinutes: 15,
                directionMode: .bidirectional
            )
            XCTFail("Expected throw")
        } catch let err as RelavoiError {
            guard case .validation = err else {
                return XCTFail("Expected .validation, got \(err)")
            }
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testCreate_apiError_throwsAPIError() async {
        let api = makeAPI()
        let mgr = SessionManagerImpl(api: api)

        enqueueTokenRefresh()
        MockURLProtocol.enqueue { _ in
            (500, [:], Data(#"{"error":"db down"}"#.utf8))
        }

        do {
            _ = try await mgr.create(
                agentPhone: "+2349000000001",
                customerPhone: "+2349000000002",
                metadata: nil,
                gracePeriodMinutes: 15,
                directionMode: .bidirectional
            )
            XCTFail("Expected throw")
        } catch let err as RelavoiError {
            guard case .api(let status, _) = err else {
                return XCTFail("Expected .api, got \(err)")
            }
            XCTAssertEqual(status, 500)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    /// The shapes a caller actually writes, and the shapes that crashed.
    ///
    /// In 0.3.0 and 0.3.1 the convenience overloads in the `SessionManager`
    /// extension forwarded to themselves, so every one of these calls recursed
    /// until the stack ran out. The process died with no assertion failure,
    /// which is why a red suite looked like a hang: this file's first test
    /// never finished and took the other six with it.
    ///
    /// Each case asserts only that the call reaches the implementation and
    /// comes back. That is the whole point: a recursing call never returns, so
    /// any assertion at all after the call is the guard.
    func testConvenienceCallsReachTheImplementation() async throws {
        let api = makeAPI()
        let mgr = SessionManagerImpl(api: api)

        // Two arguments: the minimal call, and the one the sample app makes.
        enqueueTokenRefresh()
        MockURLProtocol.enqueue { _ in (201, ["Content-Type": "application/json"], Data(self.sessionJSON(id: "min").utf8)) }
        let minimal = try await mgr.create(
            agentPhone: "+2349000000001",
            customerPhone: "+2349000000002"
        )
        XCTAssertEqual(minimal.id, "min")

        // Three: the form in the README and in SampleApp/ContentView.swift.
        MockURLProtocol.enqueue { _ in (201, ["Content-Type": "application/json"], Data(self.sessionJSON(id: "meta").utf8)) }
        let withMetadata = try await mgr.create(
            agentPhone: "+2349000000001",
            customerPhone: "+2349000000002",
            metadata: ["orderId": "ORD-1"]
        )
        XCTAssertEqual(withMetadata.id, "meta")

        // All five, which resolves to the requirement rather than the
        // convenience and so was the only shape that worked.
        MockURLProtocol.enqueue { _ in (201, ["Content-Type": "application/json"], Data(self.sessionJSON(id: "full").utf8)) }
        let full = try await mgr.create(
            agentPhone: "+2349000000001",
            customerPhone: "+2349000000002",
            metadata: nil,
            gracePeriodMinutes: 30,
            directionMode: .aToBOnly
        )
        XCTAssertEqual(full.id, "full")
    }

    /// `list()` carried the same defect, from the same cause.
    func testListWithNoArgumentsReachesTheImplementation() async throws {
        let api = makeAPI()
        let mgr = SessionManagerImpl(api: api)

        enqueueTokenRefresh()
        let listJSON = """
        {
          "data": [\(sessionJSON(id: "only"))],
          "pagination": {"count": 1, "after": null}
        }
        """
        MockURLProtocol.enqueue { _ in
            (200, ["Content-Type": "application/json"], Data(listJSON.utf8))
        }
        let resp = try await mgr.list()
        XCTAssertEqual(resp.data.count, 1)
        XCTAssertEqual(resp.data.first?.id, "only")
    }

    func testList_returnsPaginatedResponse() async throws {
        let api = makeAPI()
        let mgr = SessionManagerImpl(api: api)

        enqueueTokenRefresh()
        let listJSON = """
        {
          "data": [\(sessionJSON(id: "a")), \(sessionJSON(id: "b"))],
          "pagination": {"count": 2, "after": "cursor-xyz"}
        }
        """
        MockURLProtocol.enqueue { _ in
            (200, ["Content-Type": "application/json"], Data(listJSON.utf8))
        }

        let resp = try await mgr.list(state: nil, limit: 20, after: nil)
        XCTAssertEqual(resp.data.count, 2)
        XCTAssertEqual(resp.pagination.count, 2)
        XCTAssertEqual(resp.pagination.after, "cursor-xyz")
    }

    func testGet_usesCacheBranchAfterCreate() async throws {
        let api = makeAPI()
        let mgr = SessionManagerImpl(api: api)

        enqueueTokenRefresh()
        MockURLProtocol.enqueue { _ in
            (200, ["Content-Type": "application/json"], Data(self.sessionJSON(id: "cache-me").utf8))
        }

        let created = try await mgr.create(
            agentPhone: "+2349000000001",
            customerPhone: "+2349000000002",
            metadata: nil,
            gracePeriodMinutes: 15,
            directionMode: .bidirectional
        )

        // Now call get — should hit cache, NOT trigger a network call.
        let countBefore = MockURLProtocol.capturedRequests.count
        let fetched = try await mgr.get(created.id)
        let countAfter = MockURLProtocol.capturedRequests.count

        XCTAssertEqual(fetched.id, created.id)
        XCTAssertEqual(countBefore, countAfter, "get() should have served from cache without a network call")
    }

    func testInitiateCall_throwsUnexpected_whenUIKitUnavailable() async throws {
        // On iOS UIKit IS available, so the call would actually try to open the dialer.
        // We can't reliably exercise the no-UIKit branch from iOS test bundles, so this test
        // is best-effort: on iOS we skip; on a non-iOS host the no-UIKit branch would throw.
        #if canImport(UIKit)
        throw XCTSkip("UIKit is available on this test host; cannot exercise no-UIKit branch")
        #else
        let api = makeAPI()
        let mgr = SessionManagerImpl(api: api)

        enqueueTokenRefresh()
        MockURLProtocol.enqueue { _ in
            (200, ["Content-Type": "application/json"], Data(self.sessionJSON().utf8))
        }

        do {
            try await mgr.initiateCall(sessionId: "sess-1")
            XCTFail("Expected throw")
        } catch let err as RelavoiError {
            guard case .unexpected = err else {
                return XCTFail("Expected .unexpected, got \(err)")
            }
        }
        #endif
    }

    func testVerify_returnsVerificationResult() async throws {
        let api = makeAPI()
        let mgr = SessionManagerImpl(api: api)

        enqueueTokenRefresh()
        let json = """
        {
          "verified": true,
          "context": "Your rider is calling",
          "sessionId": "sess-1",
          "expiresAt": "2999-01-01T00:00:00Z"
        }
        """
        MockURLProtocol.enqueue { _ in
            (200, ["Content-Type": "application/json"], Data(json.utf8))
        }

        let result = try await mgr.verify(userPhone: "+2349000000001")
        XCTAssertTrue(result.verified)
        XCTAssertEqual(result.context, "Your rider is calling")
        XCTAssertEqual(result.sessionId, "sess-1")
    }
}
