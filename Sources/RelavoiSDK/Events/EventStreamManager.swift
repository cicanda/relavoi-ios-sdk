import Foundation

/// Public surface for the real-time event WebSocket.
public protocol EventStreamManager {

    /// Connect (or reconnect) to the event stream.
    func connect() async

    /// Disconnect and stop any auto-reconnect attempts.
    func disconnect() async

    /// Current connection state.
    var isConnected: Bool { get async }

    /// Register a handler for events. Identified by a caller-chosen string so it can be removed.
    func addListener(_ id: String, handler: @escaping (RelavoiEvent) -> Void)

    /// Remove a previously-registered listener.
    func removeListener(_ id: String)
}
