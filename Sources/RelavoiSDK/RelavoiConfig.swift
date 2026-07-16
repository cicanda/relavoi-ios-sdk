import Foundation

/// SDK-wide configuration. Pass to ``Relavoi/initialize(apiKey:apiSecret:tenantId:config:)``.
public struct RelavoiConfig {

    /// REST base URL. Defaults to production.
    public var baseURL: URL

    /// Optional explicit WebSocket URL. When `nil`, ``resolvedWebSocketURL`` is derived from
    /// ``baseURL`` by swapping the scheme (http→ws, https→wss) and appending `/ws`.
    public var webSocketURL: URL?

    /// Enable verbose `os_log` output. Off by default to keep production logs quiet.
    public var enableLogging: Bool

    /// Maximum offline queue length. When exceeded, the oldest entry is dropped.
    public var offlineQueueMaxSize: Int

    public init(
        baseURL: URL = URL(string: "https://api.relavoi.com/v1")!,
        webSocketURL: URL? = nil,
        enableLogging: Bool = false,
        offlineQueueMaxSize: Int = 100
    ) {
        self.baseURL = baseURL
        self.webSocketURL = webSocketURL
        self.enableLogging = enableLogging
        self.offlineQueueMaxSize = offlineQueueMaxSize
    }

    /// Returns the explicit ``webSocketURL`` if set, otherwise a derived value.
    public var resolvedWebSocketURL: URL {
        if let ws = webSocketURL { return ws }
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }
        switch comps.scheme?.lowercased() {
        case "https": comps.scheme = "wss"
        case "http": comps.scheme = "ws"
        default: break
        }
        // The backend serves the WebSocket at the host root (`/ws`), NOT under the
        // `/v1` API path. Ignore the base path and target `/ws` directly.
        comps.path = "/ws"
        comps.query = nil
        return comps.url ?? baseURL
    }
}
