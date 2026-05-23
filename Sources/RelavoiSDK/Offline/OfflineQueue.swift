import Foundation

/// File-backed FIFO queue for actions that need to be retried after a network drop.
///
/// - TODO: Not yet auto-wired into ``APIClient`` — host apps invoke enqueue/dequeue manually.
///   A future revision will integrate this transparently for idempotent verbs.
public final class OfflineQueue {

    public struct QueuedAction: Codable, Equatable {
        public let id: String
        public let action: String
        public let payload: String
        public let createdAt: Date

        public init(id: String, action: String, payload: String, createdAt: Date) {
            self.id = id
            self.action = action
            self.payload = payload
            self.createdAt = createdAt
        }
    }

    private let fileURL: URL
    private let maxSize: Int
    private let lock = NSLock()

    public init(maxSize: Int = 100, fileURL: URL? = nil) {
        self.maxSize = max(1, maxSize)
        if let provided = fileURL {
            self.fileURL = provided
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            let base = caches.first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.fileURL = base.appendingPathComponent("relavoi-queue.json")
        }
    }

    // MARK: - API

    public func enqueue(action: String, payload: String) {
        lock.lock()
        defer { lock.unlock() }
        var items = loadUnsafe()
        let new = QueuedAction(
            id: UUID().uuidString,
            action: action,
            payload: payload,
            createdAt: Date()
        )
        items.append(new)
        if items.count > maxSize {
            Logger.warn("offline queue full (\(items.count) > \(maxSize)) — dropping oldest")
            items.removeFirst(items.count - maxSize)
        }
        saveUnsafe(items)
    }

    public func dequeueAll() -> [QueuedAction] {
        lock.lock()
        defer { lock.unlock() }
        return loadUnsafe()
    }

    public func delete(id: String) {
        lock.lock()
        defer { lock.unlock() }
        var items = loadUnsafe()
        items.removeAll { $0.id == id }
        saveUnsafe(items)
    }

    public func size() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return loadUnsafe().count
    }

    // MARK: - File I/O

    private func loadUnsafe() -> [QueuedAction] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([QueuedAction].self, from: data)) ?? []
    }

    private func saveUnsafe(_ items: [QueuedAction]) {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Logger.warn("offline queue save failed: \(error.localizedDescription)")
        }
    }
}
