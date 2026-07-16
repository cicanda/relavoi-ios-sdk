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
public enum JSONValue: Codable, Equatable {
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

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .null: try container.encodeNil()
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }
}

// MARK: - Discriminated decoder

internal struct RelavoiEventDecoder {

    /// Decode a raw text frame into a ``RelavoiEvent``.
    ///
    /// Backend frames are shaped `{ "type": "...", "payload": { ... }, "id": "..." }`
    /// — the event fields live under `payload`, and the timestamp field is
    /// `timestamp` (an ISO-8601 string with fractional seconds).
    static func decode(_ data: Data) throws -> RelavoiEvent {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = APIClient.dateDecodingStrategy

        let frame = try decoder.decode(Frame.self, from: data)
        let p = frame.payload ?? EventPayload(
            sessionId: nil, proxyNumber: nil, callerNumber: nil,
            durationSeconds: nil, timestamp: nil, ts: nil
        )
        let ts = p.timestamp ?? p.ts ?? Date(timeIntervalSince1970: 0)

        switch frame.type {
        case "session.created":
            guard let sid = p.sessionId else { break }
            return .sessionCreated(sessionId: sid, proxyNumber: p.proxyNumber ?? "", ts: ts)
        case "session.activated":
            guard let sid = p.sessionId else { break }
            return .sessionActivated(sessionId: sid, ts: ts)
        case "session.expired":
            guard let sid = p.sessionId else { break }
            return .sessionExpired(sessionId: sid, ts: ts)
        case "call.incoming":
            guard let sid = p.sessionId else { break }
            // Backend carries the proxy number; fall back if a callerNumber is present.
            return .callIncoming(sessionId: sid, callerNumber: p.callerNumber ?? p.proxyNumber ?? "", ts: ts)
        case "call.answered":
            guard let sid = p.sessionId else { break }
            return .callAnswered(sessionId: sid, ts: ts)
        case "call.ended":
            guard let sid = p.sessionId else { break }
            return .callEnded(sessionId: sid, durationSeconds: p.durationSeconds ?? 0, ts: ts)
        case "sms.received", "sms.sent":
            guard let sid = p.sessionId else { break }
            return .smsReceived(sessionId: sid, ts: ts)
        default:
            break
        }
        let raw = (try? decoder.decode(JSONValue.self, from: data)) ?? .null
        return .unknown(type: frame.type, payload: raw)
    }

    // MARK: - Internal frame + payload shapes

    private struct Frame: Decodable {
        let type: String
        let payload: EventPayload?
    }

    private struct EventPayload: Decodable {
        let sessionId: String?
        let proxyNumber: String?
        let callerNumber: String?
        let durationSeconds: Int?
        let timestamp: Date?
        let ts: Date?
    }
}
