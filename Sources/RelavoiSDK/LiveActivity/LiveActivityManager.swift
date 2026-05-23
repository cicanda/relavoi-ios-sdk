#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Manages the lifecycle of the Relavoi active-call Live Activity.
///
/// The host app must enable Live Activities in `Info.plist` (`NSSupportsLiveActivities = YES`)
/// and ship a Widget Extension that exposes an `ActivityConfiguration<RelavoiCallAttributes>`.
@available(iOS 16.1, *)
public final class LiveActivityManager {

    private weak var current: Activity<RelavoiCallAttributes>?

    public init() {}

    /// Start a new Live Activity for an active call.
    public func start(
        sessionId: String,
        proxyNumber: String,
        otherPartyLabel: String,
        verified: Bool
    ) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Logger.warn("Live Activities not authorized by user; skipping start")
            return
        }
        let attributes = RelavoiCallAttributes(
            sessionId: sessionId,
            proxyNumber: proxyNumber,
            startedAt: Date()
        )
        let initialState = RelavoiCallAttributes.State(
            elapsedSeconds: 0,
            verified: verified,
            otherPartyLabel: otherPartyLabel
        )

        do {
            if #available(iOS 16.2, *) {
                let activity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: initialState, staleDate: nil)
                )
                current = activity
            } else {
                let activity = try Activity.request(
                    attributes: attributes,
                    contentState: initialState,
                    pushType: nil
                )
                current = activity
            }
        } catch let err as ActivityAuthorizationError {
            Logger.warn("ActivityAuthorizationError: \(err.localizedDescription)")
        } catch {
            throw RelavoiError.unexpected("Live Activity start failed: \(error.localizedDescription)")
        }
    }

    /// Push an updated state to the running Live Activity (e.g. on each tick).
    public func update(state: RelavoiCallAttributes.State) async {
        guard let activity = current else { return }
        if #available(iOS 16.2, *) {
            await activity.update(.init(state: state, staleDate: nil))
        } else {
            await activity.update(using: state)
        }
    }

    /// End the Live Activity. Defaults to immediate dismissal.
    public func end(dismissPolicy: ActivityUIDismissalPolicy = .immediate) async {
        guard let activity = current else { return }
        if #available(iOS 16.2, *) {
            await activity.end(nil, dismissalPolicy: dismissPolicy)
        } else {
            await activity.end(dismissalPolicy: dismissPolicy)
        }
        current = nil
    }
}
#endif
