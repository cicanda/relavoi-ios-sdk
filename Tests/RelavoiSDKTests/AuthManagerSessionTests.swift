import XCTest
@testable import RelavoiSDK

/// The `/auth/token` call must go through the session the SDK was given, not
/// `URLSession.shared`.
///
/// This mock is deliberately **never** registered with
/// `URLProtocol.registerClass`. It is reachable only through the
/// `protocolClasses` of one specific `URLSessionConfiguration`, so a request
/// that arrives here proves the injected session was used. If `AuthManager`
/// went back to `URLSession.shared`, nothing would intercept the request and
/// these tests would fail rather than quietly pass against a global
/// registration somebody else's `setUp` left behind.
private final class SessionScopedProtocol: URLProtocol {
    static let lock = NSLock()
    static var requests: [URLRequest] = []
    /// Set on the configuration, read back from the intercepted request, so
    /// the assertion is about this configuration and not about any session.
    static let marker = "X-Relavoi-Test-Marker"

    static func reset() {
        lock.lock()
        requests.removeAll()
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        Self.lock.unlock()

        let body = Data(#"{"accessToken":"jwt-from-the-injected-session","expiresIn":900}"#.utf8)
        let resp = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class AuthManagerSessionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        SessionScopedProtocol.reset()
    }

    private func scopedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionScopedProtocol.self]
        // Configuration that only a request on THIS session can carry.
        config.httpAdditionalHeaders = [SessionScopedProtocol.marker: "yes"]
        return URLSession(configuration: config)
    }

    func testTokenCallUsesTheInjectedSession() async throws {
        let store = TokenStore(tenantId: "injected-\(UUID().uuidString)")
        store.clear()
        let auth = AuthManager(
            apiKey: "sk_test",
            apiSecret: "secret",
            tenantId: "injected",
            baseURL: URL(string: "https://api.relavoi.com/v1")!,
            tokenStore: store,
            session: scopedSession()
        )

        let token = try await auth.getValidToken()
        XCTAssertEqual(token, "jwt-from-the-injected-session")

        SessionScopedProtocol.lock.lock()
        let seen = SessionScopedProtocol.requests
        SessionScopedProtocol.lock.unlock()

        // The request reached a protocol class that exists only on that one
        // configuration, so it cannot have gone through URLSession.shared.
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.url?.path, "/v1/auth/token")
        XCTAssertEqual(seen.first?.httpMethod, "POST")
    }

    /// And the session's own configuration applies to it, which is the point:
    /// a host app setting timeouts, a proxy or extra headers gets them on the
    /// token call too, not on every request except that one.
    func testTheSessionConfigurationAppliesToTheTokenCall() async throws {
        let store = TokenStore(tenantId: "injected-\(UUID().uuidString)")
        store.clear()
        let auth = AuthManager(
            apiKey: "sk_test",
            apiSecret: "secret",
            tenantId: "injected",
            baseURL: URL(string: "https://api.relavoi.com/v1")!,
            tokenStore: store,
            session: scopedSession()
        )

        _ = try await auth.getValidToken()

        SessionScopedProtocol.lock.lock()
        let seen = SessionScopedProtocol.requests.first
        SessionScopedProtocol.lock.unlock()

        XCTAssertEqual(
            seen?.value(forHTTPHeaderField: SessionScopedProtocol.marker),
            "yes",
            "the header came from httpAdditionalHeaders on the injected session's configuration"
        )
    }
}
