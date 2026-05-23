import XCTest
@testable import RelavoiSDK

// MARK: - Mock URLProtocol

/// Reusable URLProtocol mock. Tests register response handlers; each handler returns
/// (statusCode, headers, body). Multiple calls dequeue in FIFO order so we can test 401-then-200.
final class MockURLProtocol: URLProtocol {

    typealias Handler = (URLRequest) throws -> (Int, [String: String], Data)

    static let queueLock = NSLock()
    static var handlers: [Handler] = []
    static var capturedRequests: [URLRequest] = []

    static func enqueue(_ handler: @escaping Handler) {
        queueLock.lock()
        handlers.append(handler)
        queueLock.unlock()
    }

    static func reset() {
        queueLock.lock()
        handlers.removeAll()
        capturedRequests.removeAll()
        queueLock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.queueLock.lock()
        Self.capturedRequests.append(request)
        let handler: Handler? = Self.handlers.isEmpty ? nil : Self.handlers.removeFirst()
        Self.queueLock.unlock()

        guard let handler = handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        do {
            let (status, headers, body) = try handler(request)
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Test helpers

private func makeAPIClient(enableLogging: Bool = false) -> (APIClient, AuthManager) {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self] + (config.protocolClasses ?? [])
    let session = URLSession(configuration: config)

    let tokenStore = TokenStore(tenantId: "test-tenant-\(UUID().uuidString)")
    tokenStore.clear()
    let auth = AuthManager(
        apiKey: "sk_test",
        apiSecret: "secret",
        tenantId: "test-tenant",
        baseURL: URL(string: "https://api.relavoi.com/v1")!,
        tokenStore: tokenStore
    )
    let api = APIClient(
        baseURL: URL(string: "https://api.relavoi.com/v1")!,
        session: session,
        authManager: auth,
        enableLogging: enableLogging
    )
    return (api, auth)
}

private struct Pong: Decodable, Equatable { let ok: Bool; let n: Int }

// MARK: - Tests

final class APIClientTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        // Register globally too so AuthManager (URLSession.shared) is intercepted.
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testGet_addsBearerHeader() async throws {
        let (api, _) = makeAPIClient()

        // /auth/token (called by AuthManager.getValidToken) then /ping.
        MockURLProtocol.enqueue { _ in
            let body = Data(#"{"accessToken":"jwt-123","expiresIn":900}"#.utf8)
            return (200, ["Content-Type": "application/json"], body)
        }
        MockURLProtocol.enqueue { _ in
            let body = Data(#"{"ok":true,"n":1}"#.utf8)
            return (200, ["Content-Type": "application/json"], body)
        }

        let pong: Pong = try await api.get("/ping")
        XCTAssertEqual(pong, Pong(ok: true, n: 1))

        // Inspect the captured /ping request — must have Authorization: Bearer jwt-123.
        let ping = MockURLProtocol.capturedRequests.first { $0.url?.path.hasSuffix("/ping") == true }
        XCTAssertNotNil(ping)
        XCTAssertEqual(ping?.value(forHTTPHeaderField: "Authorization"), "Bearer jwt-123")
    }

    func testGet_retriesOnce_onUnauthorized() async throws {
        let (api, _) = makeAPIClient()

        // 1. Initial /auth/token
        MockURLProtocol.enqueue { _ in
            (200, ["Content-Type": "application/json"], Data(#"{"accessToken":"jwt-first","expiresIn":900}"#.utf8))
        }
        // 2. /thing — 401
        MockURLProtocol.enqueue { _ in
            (401, [:], Data(#"{"error":"expired"}"#.utf8))
        }
        // 3. Token refresh after 401
        MockURLProtocol.enqueue { _ in
            (200, ["Content-Type": "application/json"], Data(#"{"accessToken":"jwt-second","expiresIn":900}"#.utf8))
        }
        // 4. /thing retry — 200
        MockURLProtocol.enqueue { _ in
            (200, ["Content-Type": "application/json"], Data(#"{"ok":true,"n":2}"#.utf8))
        }

        let pong: Pong = try await api.get("/thing")
        XCTAssertEqual(pong, Pong(ok: true, n: 2))
    }

    func testGet_throwsRateLimited_on429() async {
        let (api, _) = makeAPIClient()

        MockURLProtocol.enqueue { _ in
            (200, ["Content-Type": "application/json"], Data(#"{"accessToken":"jwt","expiresIn":900}"#.utf8))
        }
        MockURLProtocol.enqueue { _ in
            (429, ["Retry-After": "42"], Data(#"{"error":"rate limited"}"#.utf8))
        }

        do {
            let _: Pong = try await api.get("/thing")
            XCTFail("Expected throw")
        } catch let err as RelavoiError {
            guard case .rateLimited(let retry) = err else {
                return XCTFail("Expected .rateLimited, got \(err)")
            }
            XCTAssertEqual(retry, 42)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testGet_throwsAPIError_on500() async {
        let (api, _) = makeAPIClient()

        MockURLProtocol.enqueue { _ in
            (200, ["Content-Type": "application/json"], Data(#"{"accessToken":"jwt","expiresIn":900}"#.utf8))
        }
        MockURLProtocol.enqueue { _ in
            (500, [:], Data(#"{"error":"boom"}"#.utf8))
        }

        do {
            let _: Pong = try await api.get("/thing")
            XCTFail("Expected throw")
        } catch let err as RelavoiError {
            guard case .api(let status, let body) = err else {
                return XCTFail("Expected .api, got \(err)")
            }
            XCTAssertEqual(status, 500)
            XCTAssertNotNil(body)
            XCTAssertTrue(body?.contains("boom") == true)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
}
