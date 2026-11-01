import XCTest
@testable import RelavoiSDK

/// The point of the token provider is that the SDK can work with no secret in
/// the process at all. These assert exactly that.
final class TokenProviderTests: XCTestCase {

    override func tearDown() {
        Relavoi._resetForTesting()
        super.tearDown()
    }

    func testInitializesWithNoSecretAnywhere() async throws {
        let asked = Counter()
        Relavoi.initialize(tenantId: "tenant-uuid") {
            await asked.bump()
            return RelavoiToken(accessToken: "device-token", expiresIn: 900)
        }

        // Up, with a provider and no credentials in sight.
        XCTAssertNotNil(Relavoi._sharedIfInitialized)
        XCTAssertEqual(Relavoi.shared.tenantId, "tenant-uuid")
    }

    func testAsksTheProviderForATokenAndCachesIt() async throws {
        let asked = Counter()
        let store = TokenStore(tenantId: "tenant-uuid")
        store.clear()

        let auth = AuthManager(
            source: .provider {
                await asked.bump()
                return RelavoiToken(accessToken: "device-token", expiresIn: 900)
            },
            tenantId: "tenant-uuid",
            baseURL: URL(string: "https://api.relavoi.com/v1")!,
            tokenStore: store
        )

        let first = try await auth.getValidToken()
        let second = try await auth.getValidToken()

        XCTAssertEqual(first, "device-token")
        XCTAssertEqual(second, "device-token")
        // Cached: a provider that costs a network round trip should not be
        // called twice for one token's lifetime.
        let count = await asked.value
        XCTAssertEqual(count, 1)
    }

    func testAProviderTokenIsNotPersisted() async throws {
        let store = TokenStore(tenantId: "tenant-persist-check")
        store.clear()

        let auth = AuthManager(
            source: .provider { RelavoiToken(accessToken: "device-token", expiresIn: 900) },
            tenantId: "tenant-persist-check",
            baseURL: URL(string: "https://api.relavoi.com/v1")!,
            tokenStore: store
        )
        _ = try await auth.getValidToken()

        // Nothing in the Keychain: the provider can always mint another, and a
        // persisted one would outlive a sign-out in the host app.
        XCTAssertNil(store.load())
    }

    func testAnEmptyTokenFromTheProviderIsAnError() async {
        let auth = AuthManager(
            source: .provider { RelavoiToken(accessToken: "", expiresIn: 900) },
            tenantId: "tenant-uuid",
            baseURL: URL(string: "https://api.relavoi.com/v1")!,
            tokenStore: TokenStore(tenantId: "tenant-uuid")
        )
        do {
            _ = try await auth.getValidToken()
            XCTFail("expected an error for an empty accessToken")
        } catch {
            // Any error will do; the point is that it does not silently carry
            // on and send an empty Authorization header on every request.
        }
    }
}

/// A tiny actor, so the tests can count provider calls without a data race.
private actor Counter {
    private(set) var value = 0
    func bump() { value += 1 }
}
