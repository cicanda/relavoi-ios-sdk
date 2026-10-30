import Foundation

/// Phone-number helpers used throughout the SDK.
///
/// This used to enforce strict E.164 with `^\+[1-9]\d{6,14}$`, and that was
/// wrong in both directions. It accepted numbers the API refuses, such as a +44
/// mobile or a Nigerian landline, so the SDK promised a session it could not
/// get. More awkwardly it REFUSED the forms the API accepts: someone typing
/// `08031234567`, or pasting `0803 123 4567` out of Contacts, got a client-side
/// error for a number the server would have taken.
///
/// So the client-side check is now deliberately light. The server owns the rule
/// -- it reads it from the countries table and can change it without a new SDK
/// release -- and this only catches what is obviously not a phone number, such
/// as an empty field or a name typed in the wrong box. Anything number-shaped
/// goes to the server, and the server's refusal comes back as
/// ``RelavoiError/numberNotSupported(detail:)``.
///
/// Separators are stripped using the same set the server strips, so a value the
/// API would accept is never rejected here. Keeping the two lists in step is the
/// whole point; if the server's set changes, change this one.
///
/// Nothing here ever puts any part of a number into a message. The caller passed
/// the value in, so repeating it buys nothing, and these strings reach the
/// unified log and crash reporters.
enum PhoneUtils {

    /// Spaces, brackets, hyphens, dots, the non-breaking space and the Unicode
    /// dash range. Mirrors `strip()` in the backend's phone service.
    private static let separators: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.insert(charactersIn: "()-.")
        set.insert("\u{00A0}")
        for scalar in 0x2010...0x2015 {
            if let u = Unicode.Scalar(scalar) { set.insert(u) }
        }
        return set
    }()

    /// Remove the separators a person types or Contacts carries. The result is
    /// what gets sent, so a value in a URL or a JSON body is always plain digits
    /// with an optional plus.
    static func canonicalise(_ phone: String) -> String {
        phone.components(separatedBy: separators).joined()
    }

    /// True if `phone` could be a phone number. Says nothing about which country.
    static func looksLikeNumber(_ phone: String) -> Bool {
        let canonical = canonicalise(phone)
        guard !canonical.isEmpty else { return false }

        var digits = Substring(canonical)
        if digits.first == "+" { digits = digits.dropFirst() }
        guard !digits.isEmpty else { return false }
        return digits.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// Returns the canonical form of `phone`, or throws
    /// ``RelavoiError/validation(detail:)`` if it is not number-shaped.
    ///
    /// The thrown detail names the field and describes the expected shape. It
    /// does not contain the value, not even a few digits of it.
    @discardableResult
    static func requireNumberShaped(_ phone: String, fieldName: String) throws -> String {
        guard looksLikeNumber(phone) else {
            throw RelavoiError.validation(
                detail: "\(fieldName) is not a phone number. Expected digits, optionally starting with '+'."
            )
        }
        return canonicalise(phone)
    }

    /// Percent-encode a value for use in a URL query string. Unlike
    /// `.urlQueryAllowed`, this also encodes `+` (→ `%2B`), which query parsers
    /// otherwise decode as a space — corrupting E.164 numbers.
    static func queryEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
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
