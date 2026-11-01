import Foundation

/// The Relavoi iOS SDK root.
///
/// Call ``Relavoi/initialize(apiKey:apiSecret:tenantId:config:)`` once at app startup, then
/// reach into subsystems via ``Relavoi/shared``.
///
/// Relavoi provides B2B phone-number masking for the Nigerian market. All public surface here is
/// stable; internal implementations are wired through a shared ``AuthManager`` and ``APIClient``.
public final class Relavoi {

    // MARK: - Singleton plumbing

    private static var _shared: Relavoi?
    private static let initLock = NSLock()

    /// Returns the shared instance.
    ///
    /// - Important: ``Relavoi/initialize(apiKey:apiSecret:tenantId:config:)`` must be called first.
    ///   Accessing this before init will `fatalError`.
    public static var shared: Relavoi {
        initLock.lock()
        defer { initLock.unlock() }
        guard let s = _shared else {
            fatalError("Relavoi.shared accessed before Relavoi.initialize(...) was called.")
        }
        return s
    }

    /// Initialize the SDK with a token provider. Use this one.
    ///
    /// Your app supplies a closure that asks your own backend for a token; the
    /// backend holds the API secret and calls `POST /v1/auth/sdk-token`. The
    /// secret never reaches the handset.
    ///
    /// ```swift
    /// Relavoi.initialize(tenantId: "your-tenant-uuid") {
    ///     try await MyBackend.relavoiToken()
    /// }
    /// ```
    ///
    /// Safe to call multiple times; later calls replace the instance.
    public static func initialize(
        tenantId: String,
        config: RelavoiConfig = RelavoiConfig(),
        tokenProvider: @escaping RelavoiTokenProvider
    ) {
        initLock.lock()
        defer { initLock.unlock() }
        _shared = Relavoi(
            source: .provider(tokenProvider),
            tenantId: tenantId,
            config: config
        )
    }

    /// Initialize with an API key and secret.
    ///
    /// - Warning: Do not ship a **live** key and secret in an app you
    ///   distribute. An app bundle is an archive: a constant compiled into it
    ///   can be read back out with `unzip` and `strings`, and a live pair lets
    ///   anyone create sessions billed to you and list every session and call
    ///   on your workspace.
    ///
    ///   Use this with a sandbox key while you are developing, and move to
    ///   ``initialize(tenantId:config:tokenProvider:)`` before you ship.
    @available(
        *,
        deprecated,
        message: "Ship a token provider instead: initialize(tenantId:config:tokenProvider:). A secret compiled into an app can be read back out of it."
    )
    public static func initialize(
        apiKey: String,
        apiSecret: String,
        tenantId: String,
        config: RelavoiConfig = RelavoiConfig()
    ) {
        // A sandbox key in a shipped app is a nuisance; a live one is a
        // credential anybody can take. Say so at runtime, because a compiler
        // warning is easy to silence and this one is worth reading twice.
        if apiKey.hasPrefix("rk_live_") {
            Logger.warn(
                """
                Relavoi: a LIVE API secret is compiled into this app. It can be                 extracted from the bundle, and it can create sessions billed to                 you and read every session on your workspace. Move to                 Relavoi.initialize(tenantId:config:tokenProvider:).
                """
            )
        }

        initLock.lock()
        defer { initLock.unlock() }
        _shared = Relavoi(
            source: .credentials(apiKey: apiKey, apiSecret: apiSecret),
            tenantId: tenantId,
            config: config
        )
    }

    /// Test/internal hook — allows tests to reset the singleton between cases.
    internal static func _resetForTesting() {
        initLock.lock()
        defer { initLock.unlock() }
        _shared = nil
    }

    /// Non-trapping accessor used by ``Logger`` and other internal infra that should NOT crash
    /// if the SDK hasn't been initialized yet.
    internal static var _sharedIfInitialized: Relavoi? {
        initLock.lock()
        defer { initLock.unlock() }
        return _shared
    }

    // MARK: - Public subsystems

    public let sessions: SessionManager
    public let events: EventStreamManager
    public let verification: CallVerificationManager
    public let push: PushTokenManager
    public let presence: PresenceManager

    // MARK: - Internal config exposure (for Logger gating, etc.)

    internal let config: RelavoiConfig
    internal let tenantId: String

    // MARK: - Init

    private init(source: AuthManager.Source, tenantId: String, config: RelavoiConfig) {
        self.config = config
        self.tenantId = tenantId

        let tokenStore = TokenStore(tenantId: tenantId)
        let auth = AuthManager(
            source: source,
            tenantId: tenantId,
            baseURL: config.baseURL,
            tokenStore: tokenStore
        )
        let api = APIClient(
            baseURL: config.baseURL,
            session: .shared,
            authManager: auth,
            enableLogging: config.enableLogging
        )

        self.sessions = SessionManagerImpl(api: api)
        self.events = EventStreamManagerImpl(
            webSocketURL: config.resolvedWebSocketURL,
            authManager: auth
        )
        self.verification = CallVerificationManagerImpl(api: api)
        self.push = PushTokenManager(api: api)
        self.presence = PresenceManager(api: api)
    }
}
