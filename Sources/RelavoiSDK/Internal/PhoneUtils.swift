import Foundation

/// Phone-number helpers used throughout the SDK.
///
/// All public APIs that accept phone numbers MUST pass them through ``requireValidE164(_:fieldName:)``
/// at the SDK boundary. Plaintext phones must NEVER appear in logs — use ``mask(_:)``.
enum PhoneUtils {

    /// Permissive E.164: leading `+`, first digit 1–9, then 6–14 more digits (7–15 total).
    private static let e164Pattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: "^\\+[1-9]\\d{6,14}$")
    }()

    /// Validate E.164 form.
    static func validateE164(_ phone: String) -> Bool {
        let range = NSRange(phone.startIndex..<phone.endIndex, in: phone)
        return e164Pattern.firstMatch(in: phone, options: [], range: range) != nil
    }

    /// Throw ``RelavoiError/validation(detail:)`` if `phone` is not E.164.
    /// The thrown detail message contains the field name + the last 4 digits only (privacy).
    static func requireValidE164(_ phone: String, fieldName: String) throws {
        if validateE164(phone) { return }
        let suffix = String(phone.suffix(4))
        throw RelavoiError.validation(
            detail: "\(fieldName) is not valid E.164 (got: ****\(suffix))"
        )
    }

    /// Returns a redacted form like `+****1234` suitable for logs.
    static func mask(_ phone: String) -> String {
        let last4 = String(phone.suffix(4))
        return "+****\(last4)"
    }

    /// Stable hex SHA-256 of the input. Uses CommonCrypto via `@_silgen_name` interop so we don't
    /// need to import the CommonCrypto module (which is awkward in SwiftPM).
    static func hashClientSide(_ phone: String) -> String {
        let data = Array(phone.utf8)
        var digest = [UInt8](repeating: 0, count: 32) // SHA-256 = 32 bytes
        _ = data.withUnsafeBufferPointer { buf in
            CC_SHA256(buf.baseAddress, UInt32(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// CommonCrypto C interop without importing the module.
// CC_SHA256(data: UnsafeRawPointer?, len: CC_LONG, md: UnsafeMutablePointer<UInt8>) -> UnsafeMutablePointer<UInt8>?
@_silgen_name("CC_SHA256")
@discardableResult
private func CC_SHA256(_ data: UnsafeRawPointer?, _ len: UInt32, _ md: UnsafeMutablePointer<UInt8>?) -> UnsafeMutablePointer<UInt8>?
