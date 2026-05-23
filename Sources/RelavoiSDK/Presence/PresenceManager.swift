import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Reports app lifecycle / presence state to the backend.
///
/// Call ``setUserPhone(_:)`` once you know which user is signed in; the manager is a no-op until
/// then. Observers are detached automatically on `deinit`.
public final class PresenceManager {

    private let api: APIClient
    private var userPhone: String?
    #if canImport(UIKit)
    private var observers: [NSObjectProtocol] = []
    #endif
    private let lock = NSLock()

    internal init(api: APIClient) {
        self.api = api
        installObservers()
    }

    deinit {
        #if canImport(UIKit)
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
        #endif
    }

    /// Set the user phone associated with the current app session. Required for any presence
    /// updates to be sent.
    public func setUserPhone(_ phone: String) {
        lock.lock()
        userPhone = phone
        lock.unlock()
    }

    /// Send a presence update. Public so host apps can also force-update.
    public func updatePresence(_ status: String) async {
        lock.lock()
        let phone = userPhone
        lock.unlock()
        guard let phone = phone else { return }

        struct Body: Encodable {
            let userPhone: String
            let status: String
        }
        do {
            let _: EmptyResponse = try await api.post("/devices/presence", body: Body(userPhone: phone, status: status))
        } catch {
            Logger.warn("presence update failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Lifecycle

    private func installObservers() {
        #if canImport(UIKit)
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.updatePresence("online") }
        })
        observers.append(center.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.updatePresence("background") }
        })
        observers.append(center.addObserver(
            forName: UIApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.updatePresence("offline") }
        })
        #endif
    }
}
