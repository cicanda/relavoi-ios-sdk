import XCTest
@testable import RelavoiSDK

final class PhoneUtilsTests: XCTestCase {

    // MARK: - The forms the API accepts must all pass
    //
    // This is the half the old strict-E.164 check got wrong in the expensive
    // direction: it refused what the server takes, so someone typing their own
    // Nigerian number the normal way got a client-side error.

    func testAcceptsTheFormsTheApiAccepts() {
        let accepted = [
            "08031234567",        // local
            "2348031234567",      // country code, no plus
            "+2348031234567",     // E.164
            "0803 123 4567",      // spaces
            "+234 803 123 4567",
            "(0803) 123-4567",    // brackets and a hyphen
            "0803.123.4567",
            "  +2348031234567  ", // padded
            "0803\u{00A0}123\u{00A0}4567", // non-breaking spaces, from Contacts
            "0803\u{2013}123\u{2013}4567", // en dashes, from pasted text
        ]
        for phone in accepted {
            XCTAssertTrue(PhoneUtils.looksLikeNumber(phone), "should accept: \(phone.count) chars")
        }
    }

    func testDoesNotJudgeTheCountry() {
        // A UK number and a Nigerian landline are both number-shaped. The SDK
        // sends them and the API refuses them, which is the point: the rule can
        // change server-side without a new SDK release.
        XCTAssertTrue(PhoneUtils.looksLikeNumber("+447911123456"))
        XCTAssertTrue(PhoneUtils.looksLikeNumber("+2341234567"))
    }

    // MARK: - Only the obvious mistakes are refused

    func testRejectsValuesThatAreNotNumbers() {
        let rejected = ["", "   ", "+", "Ada Obi", "+234ABC5678", "null", "+234-803-ABCD", "()"]
        for phone in rejected {
            XCTAssertFalse(PhoneUtils.looksLikeNumber(phone), "should reject: \(phone.count) chars")
        }
    }

    func testRejectsAPlusThatIsNotLeading() {
        XCTAssertFalse(PhoneUtils.looksLikeNumber("234+8031234567"))
        XCTAssertFalse(PhoneUtils.looksLikeNumber("08031234567+"))
    }

    func testRejectsNonAsciiDigits() {
        // Arabic-Indic digits are Characters where isNumber is true. They are not
        // something a carrier can dial, and allowing them would send a value the
        // server would reject with a less clear message.
        XCTAssertFalse(PhoneUtils.looksLikeNumber("٠٨٠٣١٢٣٤٥٦٧"))
    }

    // MARK: - canonicalise

    func testCanonicaliseStripsSeparatorsAndKeepsLeadingPlus() {
        XCTAssertEqual(PhoneUtils.canonicalise("+234 803 123 4567"), "+2348031234567")
        XCTAssertEqual(PhoneUtils.canonicalise("(0803) 123-4567"), "08031234567")
        XCTAssertEqual(PhoneUtils.canonicalise("  +2348031234567  "), "+2348031234567")
    }

    func testRequireNumberShapedReturnsTheCanonicalForm() throws {
        let canonical = try PhoneUtils.requireNumberShaped("0803 123 4567", fieldName: "agentPhone")
        XCTAssertEqual(canonical, "08031234567")
    }

    // MARK: - No part of a number in any message

    func testValidationMessageNamesTheFieldAndCarriesNoDigits() {
        do {
            _ = try PhoneUtils.requireNumberShaped("0803123XXXX", fieldName: "agentPhone")
            XCTFail("expected a validation error")
        } catch let error as RelavoiError {
            guard case .validation(let detail) = error else {
                return XCTFail("expected .validation, got \(error)")
            }
            XCTAssertTrue(detail.contains("agentPhone"))
            // The old implementation appended the last four characters.
            XCTAssertFalse(detail.contains(where: { $0.isNumber }), "no digits of the input")
            XCTAssertFalse(detail.contains("XXXX"))
            XCTAssertFalse(detail.contains("0803"))
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testValidationPassesSilentlyOnAcceptableInput() throws {
        try PhoneUtils.requireNumberShaped("+2348031234567", fieldName: "x")
        try PhoneUtils.requireNumberShaped("08031234567", fieldName: "x")
    }

    // MARK: - queryEncode

    func testQueryEncodeEscapesThePlus() {
        // A query parser decodes a bare '+' as a space, which corrupts the number.
        XCTAssertEqual(PhoneUtils.queryEncode("+2348031234567"), "%2B2348031234567")
    }
}

final class APIClientErrorMappingTests: XCTestCase {

    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testMapsNumberNotSupported() {
        let body = data("""
        {"type":"https://api.relavoi.com/errors/number-not-supported","status":422,
         "detail":"Relavoi currently connects Nigerian mobile numbers only."}
        """)
        guard case .numberNotSupported(let detail) = APIClient.error(status: 422, data: body) else {
            return XCTFail("expected .numberNotSupported")
        }
        XCTAssertEqual(detail, "Relavoi currently connects Nigerian mobile numbers only.")
    }

    func testMapsCrossBorderNotSupported() {
        let body = data("""
        {"type":"https://api.relavoi.com/errors/cross-border-not-supported","status":422,
         "detail":"Both people in a session must have numbers from the same country."}
        """)
        guard case .crossBorderNotSupported(let detail) = APIClient.error(status: 422, data: body) else {
            return XCTFail("expected .crossBorderNotSupported")
        }
        XCTAssertTrue(detail.contains("same country"))
    }

    func testMapsNumberQuotaReachedOn409() {
        let body = data("""
        {"type":"https://api.relavoi.com/errors/number-quota-reached","status":409,
         "detail":"This workspace is holding all 1 of its 1 proxy numbers."}
        """)
        guard case .numberQuotaReached(let detail) = APIClient.error(status: 409, data: body) else {
            return XCTFail("expected .numberQuotaReached")
        }
        XCTAssertTrue(detail.contains("proxy numbers"))
    }

    func testNumberQuotaReachedIsNotARateLimitEvenOn429() {
        // It was answered with a 429 before the status was changed to 409. An
        // SDK that keyed on the status would have called it a rate limit, and
        // a caller handling `rateLimited` retries. The slug decides, so an old
        // backend and a new one both read correctly.
        let body = data("""
        {"type":"https://api.relavoi.com/errors/number-quota-reached","status":429,
         "detail":"At the limit."}
        """)
        guard case .numberQuotaReached = APIClient.error(status: 429, data: body) else {
            return XCTFail("expected .numberQuotaReached, not .rateLimited")
        }
    }

    func testAPlainRateLimitIsStillARateLimit() {
        let body = data(#"{"type":"https://api.relavoi.com/errors/rate-limit","status":429,"detail":"Slow down."}"#)
        guard case .api = APIClient.error(status: 429, data: body) else {
            return XCTFail("expected the generic mapping; the 429 branch is in send()")
        }
    }

    func testMapsAnyOther422ToValidation() {
        let body = data(#"{"type":"https://api.relavoi.com/errors/validation","status":422,"detail":"agentPhone is not valid."}"#)
        guard case .validation(let detail) = APIClient.error(status: 422, data: body) else {
            return XCTFail("expected .validation")
        }
        XCTAssertTrue(detail.contains("agentPhone"))
    }

    func testMatchesTheSlugOnAnyHost() {
        // The type URL's host differs between environments; the slug does not.
        let body = data(#"{"type":"https://staging.example.test/errors/number-not-supported","status":422,"detail":"nope"}"#)
        guard case .numberNotSupported = APIClient.error(status: 422, data: body) else {
            return XCTFail("expected .numberNotSupported")
        }
    }

    func testDoesNotSurfaceARawBody() {
        // An error page from in front of the API commonly echoes the request URI,
        // and /sessions/verify carries a subscriber's number in its query string.
        let error = APIClient.error(status: 502, data: data("<html>bad gateway /v1/sessions/verify?userPhone=%2B2348031234567</html>"))
        guard case .api(let status, let body) = error else {
            return XCTFail("expected .api")
        }
        XCTAssertEqual(status, 502)
        XCTAssertNil(body)
        XCTAssertFalse((error.errorDescription ?? "").contains("2348031234567"))
    }

    func testReadsDetailOutOfAProblemDocumentOn500() {
        let body = data(#"{"type":"https://api.relavoi.com/errors/internal","status":500,"detail":"Something went wrong."}"#)
        guard case .api(let status, let detail) = APIClient.error(status: 500, data: body) else {
            return XCTFail("expected .api")
        }
        XCTAssertEqual(status, 500)
        XCTAssertEqual(detail, "Something went wrong.")
    }

    func testPathForLogDropsTheQueryString() {
        XCTAssertEqual(
            APIClient.pathForLog("/sessions/verify?userPhone=%2B2348031234567&tenantId=t"),
            "/sessions/verify"
        )
        XCTAssertEqual(APIClient.pathForLog("/sessions"), "/sessions")
    }
}
