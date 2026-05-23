#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// ActivityKit attributes for the Relavoi active-call Live Activity / Dynamic Island.
@available(iOS 16.1, *)
public struct RelavoiCallAttributes: ActivityAttributes {

    public typealias ContentState = State

    public struct State: Codable, Hashable {
        public let elapsedSeconds: Int
        public let verified: Bool
        public let otherPartyLabel: String

        public init(elapsedSeconds: Int, verified: Bool, otherPartyLabel: String) {
            self.elapsedSeconds = elapsedSeconds
            self.verified = verified
            self.otherPartyLabel = otherPartyLabel
        }
    }

    public let sessionId: String
    public let proxyNumber: String
    public let startedAt: Date

    public init(sessionId: String, proxyNumber: String, startedAt: Date) {
        self.sessionId = sessionId
        self.proxyNumber = proxyNumber
        self.startedAt = startedAt
    }
}
#endif
