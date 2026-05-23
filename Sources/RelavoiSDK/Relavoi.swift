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

    /// Initialize the SDK. Safe to call multiple times — subsequent calls replace the instance.
    public static func initialize(
        apiKey: String,
        apiSecret: String,
        tenantId: String,
        config: RelavoiConfig = RelavoiConfig()
    ) {
        initLock.lock()
        defer { initLock.unlock() }
        _shared = Relavoi(
            apiKey: apiKey,
            apiSecret: apiSecret,
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

    private init(apiKey: String, apiSecret: String, tenantId: String, config: RelavoiConfig) {
        self.config = config
        self.tenantId = tenantId

        let tokenStore = TokenStore(tenantId: tenantId)
        let auth = AuthManager(
            apiKey: apiKey,
            apiSecret: apiSecret,
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
