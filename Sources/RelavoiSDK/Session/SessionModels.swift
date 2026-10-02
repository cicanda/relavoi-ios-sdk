import Foundation

// MARK: - Public models

public struct Session: Codable, Identifiable, Equatable {
    public let id: String
    public let tenantId: String
    public let proxyNumber: String
    public let state: SessionState
    public let directionMode: DirectionMode
    // The server allows arbitrary JSON metadata values (nested objects, numbers,
    // arrays), so this is [String: JSONValue] rather than [String: String].
    public let metadata: [String: JSONValue]?
    public let gracePeriodMinutes: Int
    public let maxDurationMinutes: Int
    public let recordingEnabled: Bool
    public let consentPrompt: ConsentPrompt
    public let expiresAt: Date
    public let createdAt: Date
    public let activatedAt: Date?
    public let endedAt: Date?
    public let expiredAt: Date?
    public let callCount: Int?
    public let lastCallAt: Date?

    public init(
        id: String,
        tenantId: String,
        proxyNumber: String,
        state: SessionState,
        directionMode: DirectionMode,
        metadata: [String: JSONValue]?,
        gracePeriodMinutes: Int,
        maxDurationMinutes: Int,
        recordingEnabled: Bool,
        consentPrompt: ConsentPrompt,
        expiresAt: Date,
        createdAt: Date,
        activatedAt: Date?,
        endedAt: Date? = nil,
        expiredAt: Date? = nil,
        callCount: Int?,
        lastCallAt: Date? = nil
    ) {
        self.id = id
        self.tenantId = tenantId
        self.proxyNumber = proxyNumber
        self.state = state
        self.directionMode = directionMode
        self.metadata = metadata
        self.gracePeriodMinutes = gracePeriodMinutes
        self.maxDurationMinutes = maxDurationMinutes
        self.recordingEnabled = recordingEnabled
        self.consentPrompt = consentPrompt
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.activatedAt = activatedAt
        self.endedAt = endedAt
        self.expiredAt = expiredAt
        self.callCount = callCount
        self.lastCallAt = lastCallAt
    }
}

public enum SessionState: String, Codable {
    case pending = "PENDING"
    case active = "ACTIVE"
    case gracePeriod = "GRACE_PERIOD"
    case expired = "EXPIRED"
    case failed = "FAILED"
}

public enum DirectionMode: String, Codable {
    case bidirectional = "BIDIRECTIONAL"
    case aToBOnly = "A_TO_B_ONLY"
    case bToAOnly = "B_TO_A_ONLY"
}

public enum ConsentPrompt: String, Codable {
    case `default` = "DEFAULT"
    case custom = "CUSTOM"
    case none = "NONE"
}

public struct SessionListResponse: Decodable {
    public let data: [Session]
    public let pagination: PaginationInfo
}

public struct PaginationInfo: Decodable {
    public let count: Int
    public let after: String?
}

// MARK: - Internal request bodies

struct SwapTargetRequest: Encodable {
    let customerPhone: String
}

struct CreateSessionRequest: Encodable {
    let agentPhone: String
    let customerPhone: String
    let metadata: [String: String]?
    let gracePeriodMinutes: Int
    let directionMode: String
    let recordingEnabled: Bool
    let consentPrompt: String
}
