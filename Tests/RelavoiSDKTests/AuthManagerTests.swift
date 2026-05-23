import XCTest
@testable import RelavoiSDK

/// AuthManager uses `URLSession.shared` directly (see comment in AuthManager.swift). To intercept
/// its traffic in tests we register MockURLProtocol globally via `URLProtocol.registerClass(...)`.
/// This is a documented compromise — APIClient is the cleanly-injectable path.
final class AuthManagerTests: XCTestCase {

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

    private func makeAuth() -> AuthManager {
        // Use a unique tenantId per test so Keychain entries don't leak between runs.
        let tenantId = "auth-test-\(UUID().uuidString)"
        let store = TokenStore(tenantId: tenantId)
        store.clear()
        return AuthManager(
            apiKey: "sk_test",
            apiSecret: "secret",
            tenantId: tenantId,
            baseURL: URL(string: "https://api.relavoi.com/v1")!,
            tokenStore: store
        )
    }

    func testGetValidToken_cachesAndReturns() async throws {
        let auth = makeAuth()

        // One refresh expected.
        MockURLProtocol.enqueue { _ in
            (200, ["Content-Type": "application/json"], Data(#"{"accessToken":"abc","expiresIn":900}"#.utf8))
        }

        let t1 = try await auth.getValidToken()
        XCTAssertEqual(t1, "abc")

        // Second call should hit the cache — no further mock handler dequeued.
        let t2 = try await auth.getValidToken()
        XCTAssertEqual(t2, "abc")

        // Verify only ONE network call happened.
        let authReqs = MockURLProtocol.capturedRequests.filter { $0.url?.path.contains("/auth/token") == true }
        XCTAssertEqual(authReqs.count, 1)
    }

    func testGetValidToken_refreshesNearExpiry() async throws {
        let auth = makeAuth()

        // First token expires in 30s — within the 60s refresh lead time, so the SECOND
        // getValidToken() call should refresh.
        MockURLProtocol.enqueue { _ in
            (200, ["Content-Type": "application/json"], Data(#"{"accessToken":"first","expiresIn":30}"#.utf8))
        }
        MockURLProtocol.enqueue { _ in
            (200, ["Content-Type": "application/json"], Data(#"{"accessToken":"second","expiresIn":900}"#.utf8))
        }

        let t1 = try await auth.getValidToken()
        XCTAssertEqual(t1, "first")

        let t2 = try await auth.getValidToken()
        XCTAssertEqual(t2, "second", "Should have refreshed because first token was within the 60s lead time")
    }
}
