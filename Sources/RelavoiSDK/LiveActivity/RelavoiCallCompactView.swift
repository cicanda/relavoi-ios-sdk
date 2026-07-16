#if canImport(ActivityKit) && canImport(SwiftUI)
import ActivityKit
import SwiftUI
import WidgetKit

/// Dynamic Island views for the Relavoi active-call Live Activity.
///
/// Use these from your Widget Extension `dynamicIsland` closure:
///
/// ```swift
/// ActivityConfiguration(for: RelavoiCallAttributes.self) { context in
///     RelavoiCallActivityView(context: context)
/// } dynamicIsland: { context in
///     DynamicIsland {
///         DynamicIslandExpandedRegion(.leading)  { RelavoiCallCompactView.expandedLeading(context) }
///         DynamicIslandExpandedRegion(.trailing) { RelavoiCallCompactView.expandedTrailing(context) }
///         DynamicIslandExpandedRegion(.center)   { RelavoiCallCompactView.expandedCenter(context) }
///     } compactLeading: {
///         RelavoiCallCompactView.compactLeading(context)
///     } compactTrailing: {
///         RelavoiCallCompactView.compactTrailing(context)
///     } minimal: {
///         RelavoiCallCompactView.minimal(context)
///     }
/// }
/// ```
@available(iOS 17.0, *)
public struct RelavoiCallCompactView: View {

    public let context: ActivityViewContext<RelavoiCallAttributes>

    public init(context: ActivityViewContext<RelavoiCallAttributes>) {
        self.context = context
    }

    public var body: some View {
        // Default body == compactTrailing. Most callers use the static helpers below.
        Self.compactTrailing(context)
    }

    // MARK: - Compact

    public static func compactLeading(_ context: ActivityViewContext<RelavoiCallAttributes>) -> some View {
        Circle()
            .fill(context.state.verified ? Color.green : Color.red)
            .frame(width: 10, height: 10)
            .padding(2)
    }

    public static func compactTrailing(_ context: ActivityViewContext<RelavoiCallAttributes>) -> some View {
        Text(format(context.state.elapsedSeconds))
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .foregroundColor(.primary)
            .monospacedDigit()
    }

    public static func minimal(_ context: ActivityViewContext<RelavoiCallAttributes>) -> some View {
        Circle()
            .fill(context.state.verified ? Color.green : Color.red)
            .frame(width: 8, height: 8)
    }

    // MARK: - Expanded helpers (optional)

    public static func expandedLeading(_ context: ActivityViewContext<RelavoiCallAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Relavoi")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Text(context.attributes.proxyNumber)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
        }
    }

    public static func expandedTrailing(_ context: ActivityViewContext<RelavoiCallAttributes>) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(format(context.state.elapsedSeconds))
                .font(.system(.body, design: .monospaced).weight(.semibold))
            HStack(spacing: 4) {
                Circle()
                    .fill(context.state.verified ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(context.state.verified ? "Verified" : "Unverified")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    public static func expandedCenter(_ context: ActivityViewContext<RelavoiCallAttributes>) -> some View {
        Text(context.state.otherPartyLabel)
            .font(.caption.weight(.medium))
            .foregroundColor(.primary)
            .lineLimit(1)
    }

    // MARK: - Helpers

    private static func format(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}
#endif
