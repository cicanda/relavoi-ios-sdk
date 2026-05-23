import XCTest
@testable import RelavoiSDK

final class PhoneUtilsTests: XCTestCase {

    func testValidateE164_valid() {
        let valid = [
            "+2348012345678",   // Nigerian mobile (MTN)
            "+14155552671",     // US
            "+447911123456",    // UK
            "+919876543210",    // India
            "+12025550199",     // US DC
            "+861234567",       // 7 digits — at the minimum bound
        ]
        for phone in valid {
            XCTAssertTrue(PhoneUtils.validateE164(phone), "Expected valid: \(phone)")
        }
    }

    func testValidateE164_invalid() {
        let invalid = [
            "",                       // empty
            "2348012345678",          // missing +
            "+0234567890",            // leading 0 after +
            "+",                      // just +
            "+12 34 567",             // spaces
            "+1-234-567-8901",        // dashes
            "+1234",                  // too short
            "+1234567890123456",      // too long (>15 digits)
            "+abc1234567",            // non-digits
            "+1234567890a",           // trailing letter
        ]
        for phone in invalid {
            XCTAssertFalse(PhoneUtils.validateE164(phone), "Expected invalid: \(phone)")
        }
    }

    func testRequireValidE164_throwsValidation() {
        XCTAssertThrowsError(
            try PhoneUtils.requireValidE164("not-a-phone", fieldName: "agentPhone")
        ) { err in
            guard case RelavoiError.validation(let detail) = err else {
                return XCTFail("Expected .validation, got \(err)")
            }
            XCTAssertTrue(detail.contains("agentPhone"), "Detail should include field name")
        }
    }

    func testRequireValidE164_passesForValidInput() {
        XCTAssertNoThrow(
            try PhoneUtils.requireValidE164("+2348012345678", fieldName: "x")
        )
    }

    func testMask_returnsLast4Suffix() {
        XCTAssertEqual(PhoneUtils.mask("+2348012345678"), "+****5678")
        XCTAssertEqual(PhoneUtils.mask("+14155552671"), "+****2671")
    }

    func testHashClientSide_stable() {
        let a1 = PhoneUtils.hashClientSide("+2348012345678")
        let a2 = PhoneUtils.hashClientSide("+2348012345678")
        let b = PhoneUtils.hashClientSide("+2348012345679")
        XCTAssertEqual(a1, a2, "Hash must be stable for same input")
        XCTAssertNotEqual(a1, b, "Hash must differ for different inputs")
        XCTAssertEqual(a1.count, 64, "SHA-256 hex must be 64 chars")
        // Sanity: hex only
        XCTAssertNil(a1.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789abcdef").inverted))
    }
}
