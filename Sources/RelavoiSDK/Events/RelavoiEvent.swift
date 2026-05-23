import Foundation

/// Real-time events streamed from the Relavoi backend over WebSocket.
///
/// Mirrors the Android SDK event set. Unknown event types decode into ``RelavoiEvent/unknown(type:payload:)``
/// so consumers can still log/inspect them without a crash.
public enum RelavoiEvent: Equatable {
    case sessionCreated(sessionId: String, proxyNumber: String, ts: Date)
    case sessionActivated(sessionId: String, ts: Date)
    case sessionExpired(sessionId: String, ts: Date)
    case callIncoming(sessionId: String, callerNumber: String, ts: Date)
    case callAnswered(sessionId: String, ts: Date)
    case callEnded(sessionId: String, durationSeconds: Int, ts: Date)
    case smsReceived(sessionId: String, ts: Date)
    case unknown(type: String, payload: JSONValue)
}

/// A minimal `Any`-equivalent for Codable. Swift's `Codable` can't round-trip `[String: Any]`,
/// so this small enum bridges JSON payloads cleanly.
public enum JSONValue: Decodable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let arr = try? container.decode([JSONValue].self) {
            self = .array(arr)
        } else if let obj = try? container.decode([String: JSONValue].self) {
            self = .object(obj)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "JSONValue could not decode"
            )
        }
    }
}

// MARK: - Discriminated decoder

internal struct RelavoiEventDecoder {

    /// Decode a raw text frame into a ``RelavoiEvent``.
    static func decode(_ data: Data) throws -> RelavoiEvent {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Step 1: read the "type" discriminator.
        struct TypeOnly: Decodable { let type: String }
        let typeOnly = try decoder.decode(TypeOnly.self, from: data)

        switch typeOnly.type {
        case "session.created":
            let p = try decoder.decode(SessionCreatedPayload.self, from: data)
            return .sessionCreated(sessionId: p.sessionId, proxyNumber: p.proxyNumber, ts: p.ts)
        case "session.activated":
            let p = try decoder.decode(SessionTimestampedPayload.self, from: data)
            return .sessionActivated(sessionId: p.sessionId, ts: p.ts)
        case "session.expired":
            let p = try decoder.decode(SessionTimestampedPayload.self, from: data)
            return .sessionExpired(sessionId: p.sessionId, ts: p.ts)
        case "call.incoming":
            let p = try decoder.decode(CallIncomingPayload.self, from: data)
            return .callIncoming(sessionId: p.sessionId, callerNumber: p.callerNumber, ts: p.ts)
        case "call.answered":
            let p = try decoder.decode(SessionTimestampedPayload.self, from: data)
            return .callAnswered(sessionId: p.sessionId, ts: p.ts)
        case "call.ended":
            let p = try decoder.decode(CallEndedPayload.self, from: data)
            return .callEnded(sessionId: p.sessionId, durationSeconds: p.durationSeconds, ts: p.ts)
        case "sms.received":
            let p = try decoder.decode(SessionTimestampedPayload.self, from: data)
            return .smsReceived(sessionId: p.sessionId, ts: p.ts)
        default:
            let payload = (try? decoder.decode(JSONValue.self, from: data)) ?? .null
            return .unknown(type: typeOnly.type, payload: payload)
        }
    }

    // MARK: - Internal payload shapes

    private struct SessionTimestampedPayload: Decodable {
        let sessionId: String
        let ts: Date
    }
    private struct SessionCreatedPayload: Decodable {
        let sessionId: String
        let proxyNumber: String
        let ts: Date
    }
    private struct CallIncomingPayload: Decodable {
        let sessionId: String
        let callerNumber: String
        let ts: Date
    }
    private struct CallEndedPayload: Decodable {
        let sessionId: String
        let durationSeconds: Int
        let ts: Date
    }
}
