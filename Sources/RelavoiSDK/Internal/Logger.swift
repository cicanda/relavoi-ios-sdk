import Foundation
import os

/// Internal logger. Gated by `Relavoi.shared.config.enableLogging`. Tolerant of being called
/// before `Relavoi.initialize(...)` — silently drops messages in that case.
enum Logger {

    private static let subsystem = "com.relavoi.sdk"

    private static var loggingEnabled: Bool {
        Relavoi._sharedIfInitialized?.config.enableLogging ?? false
    }

    static func debug(_ message: @autoclosure () -> String, category: String = "general") {
        guard loggingEnabled else { return }
        let log = OSLog(subsystem: subsystem, category: category)
        os_log("%{public}@", log: log, type: .debug, message())
    }

    static func info(_ message: @autoclosure () -> String, category: String = "general") {
        guard loggingEnabled else { return }
        let log = OSLog(subsystem: subsystem, category: category)
        os_log("%{public}@", log: log, type: .info, message())
    }

    static func warn(_ message: @autoclosure () -> String, category: String = "general") {
        guard loggingEnabled else { return }
        let log = OSLog(subsystem: subsystem, category: category)
        os_log("%{public}@", log: log, type: .default, message())
    }

    static func error(_ message: @autoclosure () -> String, category: String = "general") {
        guard loggingEnabled else { return }
        let log = OSLog(subsystem: subsystem, category: category)
        os_log("%{public}@", log: log, type: .error, message())
    }

    static func network(_ message: @autoclosure () -> String) {
        debug(message(), category: "network")
    }

    static func events(_ message: @autoclosure () -> String) {
        debug(message(), category: "events")
    }
}
