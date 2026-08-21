import SwiftUI

/// Thread-safe log store. SDK callbacks (e.g. the events WebSocket) fire off the
/// main thread, so `log()` always marshals the `@Published` mutation to main.
final class LogStore: ObservableObject {
    @Published var lines: [String] = []

    func log(_ message: String) {
        let line = "[\(Self.timestamp())] \(message)"
        DispatchQueue.main.async { self.lines.append(line) }
    }

    func clear() {
        DispatchQueue.main.async { self.lines.removeAll() }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}

/// Scrollable, monospaced log view that auto-scrolls to the newest line.
struct SDKLogView: View {
    @ObservedObject var store: LogStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(store.lines.enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(idx)
                    }
                }
                .padding(8)
            }
            .background(Color.black)
            .onChange(of: store.lines.count) { _ in
                if let last = store.lines.indices.last {
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }
}
