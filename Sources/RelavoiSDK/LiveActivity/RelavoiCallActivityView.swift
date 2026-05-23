#if canImport(ActivityKit) && canImport(SwiftUI)
import ActivityKit
import SwiftUI

/// Lock-screen / banner view for the Relavoi active-call Live Activity.
///
/// Render this from your Widget Extension inside an `ActivityConfiguration`:
///
/// ```swift
/// ActivityConfiguration(for: RelavoiCallAttributes.self) { context in
///     RelavoiCallActivityView(context: context)
/// } dynamicIsland: { context in
///     // see RelavoiCallCompactView
/// }
/// ```
@available(iOS 16.1, *)
public struct RelavoiCallActivityView: View {

    public let context: ActivityViewContext<RelavoiCallAttributes>

    public init(context: ActivityViewContext<RelavoiCallAttributes>) {
        self.context = context
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Brand mark — a simple rounded square placeholder, no asset dependency.
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                Text("R")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundColor(.accentColor)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Relavoi")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text("·")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Active Call")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                Text(context.attributes.proxyNumber)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .foregroundColor(.primary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(format(context.state.elapsedSeconds))
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundColor(.primary)
                HStack(spacing: 4) {
                    Circle()
                        .fill(context.state.verified ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(context.state.verified ? "Verified" : "Unverified")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func format(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}
#endif
