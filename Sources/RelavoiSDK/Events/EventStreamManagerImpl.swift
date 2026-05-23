import Foundation

/// Default WebSocket-backed implementation of ``EventStreamManager``.
///
/// - JWT is appended as a `?token=...` query parameter at connect-time.
/// - Reconnects with exponential backoff: 500ms → 1s → 2s → … capped at 30s.
actor EventStreamManagerImpl: EventStreamManager {

    // MARK: - State

    private let webSocketURL: URL
    private let authManager: AuthManager
    private let session: URLSession

    private var socket: URLSessionWebSocketTask?
    private var receiveLoopTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var manuallyDisconnected = false
    private var backoffSeconds: Double = 0.5

    /// Listeners are stored unisolated for fast addition/removal.
    private final class ListenerBox {
        let queue = DispatchQueue(label: "com.relavoi.sdk.event-listeners")
        var handlers: [String: (RelavoiEvent) -> Void] = [:]
    }
    private let listeners = ListenerBox()

    private var _connected = false

    // MARK: - Init

    init(webSocketURL: URL, authManager: AuthManager) {
        self.webSocketURL = webSocketURL
        self.authManager = authManager
        self.session = URLSession(configuration: .default)
    }

    // MARK: - EventStreamManager

    var isConnected: Bool { _connected }

    func connect() async {
        manuallyDisconnected = false
        await openSocket()
    }

    func disconnect() async {
        manuallyDisconnected = true
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        _connected = false
    }

    nonisolated func addListener(_ id: String, handler: @escaping (RelavoiEvent) -> Void) {
        listeners.queue.sync { listeners.handlers[id] = handler }
    }

    nonisolated func removeListener(_ id: String) {
        listeners.queue.sync { _ = listeners.handlers.removeValue(forKey: id) }
    }

    // MARK: - Internal

    private func openSocket() async {
        let token: String
        do {
            token = try await authManager.getValidToken()
        } catch {
            Logger.error("WS auth failed: \(error.localizedDescription)", category: "events")
            scheduleReconnect()
            return
        }

        var comps = URLComponents(url: webSocketURL, resolvingAgainstBaseURL: false)
        var items = comps?.queryItems ?? []
        items.append(URLQueryItem(name: "token", value: token))
        comps?.queryItems = items
        guard let finalURL = comps?.url else {
            Logger.error("WS URL invalid", category: "events")
            return
        }

        let task = session.webSocketTask(with: finalURL)
        socket = task
        task.resume()
        _connected = true
        backoffSeconds = 0.5
        Logger.info("WS connected", category: "events")

        receiveLoopTask = Task { [weak self] in
            await self?.receiveLoop(task: task)
        }
    }

    private func receiveLoop(task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                handle(message: message)
            } catch {
                Logger.warn("WS recv error: \(error.localizedDescription)", category: "events")
                _connected = false
                if !manuallyDisconnected {
                    scheduleReconnect()
                }
                return
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: return
        }
        do {
            let event = try RelavoiEventDecoder.decode(data)
            let snapshot = listeners.queue.sync { listeners.handlers }
            for handler in snapshot.values { handler(event) }
        } catch {
            Logger.warn("WS decode error: \(error.localizedDescription)", category: "events")
        }
    }

    private func scheduleReconnect() {
        guard !manuallyDisconnected else { return }
        let delay = min(backoffSeconds, 30.0)
        backoffSeconds = min(backoffSeconds * 2, 30.0)
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self = self, !Task.isCancelled else { return }
            await self.openSocket()
        }
    }
}
