// The app's own backend, which holds the API secret and calls
// POST /v1/auth/sdk-token. Every initialize sample reaches for it.
import RelavoiSDK

enum MyBackend {
    static func relavoiToken() async throws -> RelavoiToken {
        RelavoiToken(accessToken: "stub", expiresIn: 900)
    }
}
