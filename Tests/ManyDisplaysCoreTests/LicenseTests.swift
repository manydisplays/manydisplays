import Foundation
@testable import ManyDisplaysCore
import XCTest

final class LicenseTests: XCTestCase {
    let day = Licensing.day
    func key(until: String?, status: String = "active") -> LicenseKey {
        LicenseKey(
            key: "K",
            email: "a@b.c",
            updatesUntil: until.flatMap(day),
            status: status,
            instanceID: "i",
            validatedAt: Date()
        )
    }

    func testSourceBuildsAreFree() {
        XCTAssertEqual(LicenseState.compute(required: false, key: nil, trialStartedAt: .distantPast, buildDate: Date()), .free)
    }

    func testTrialCountsDownThenExpires() throws {
        let start = try XCTUnwrap(day("2026-10-01"))
        XCTAssertEqual(
            LicenseState.compute(required: true, key: nil, trialStartedAt: start, buildDate: start, now: start),
            .trial(daysLeft: 14)
        )
        XCTAssertEqual(
            try LicenseState
                .compute(
                    required: true,
                    key: nil,
                    trialStartedAt: start,
                    buildDate: start,
                    now: XCTUnwrap(day("2026-10-14"))
                ),
            .trial(daysLeft: 1)
        )
        XCTAssertEqual(
            try LicenseState
                .compute(
                    required: true,
                    key: nil,
                    trialStartedAt: start,
                    buildDate: start,
                    now: XCTUnwrap(day("2026-10-15"))
                ),
            .trialExpired
        )
        XCTAssertFalse(LicenseState.trialExpired.allowsRestoring)
    }

    func testLicenceCoversBuildsUpToItsUpdateWindow() throws {
        let k = key(until: "2027-10-13")
        XCTAssertEqual(
            try LicenseState
                .compute(required: true, key: k, trialStartedAt: .distantPast, buildDate: XCTUnwrap(day("2027-10-13"))),
            .licensed(k)
        )
        XCTAssertEqual(
            try LicenseState
                .compute(required: true, key: k, trialStartedAt: .distantPast, buildDate: XCTUnwrap(day("2027-10-14"))),
            .updatesExpired(k)
        )
        XCTAssertEqual(
            LicenseState.compute(required: true, key: key(until: nil), trialStartedAt: .distantPast, buildDate: .distantFuture),
            .licensed(key(until: nil))
        )
        XCTAssertEqual(
            LicenseState.compute(
                required: true,
                key: key(until: nil, status: "disabled"),
                trialStartedAt: .distantPast,
                buildDate: Date()
            ),
            .updatesExpired(key(until: nil, status: "disabled"))
        )
    }

    func testParsesActivationResponse() throws {
        let json = """
        {"activated":true,"error":null,"license_key":{"id":1,"status":"active","key":"38b1460a-5104-4067-a91d-77b872934d51",
        "activation_limit":3,"activation_usage":1,"created_at":"2026-10-13T10:00:00.000000Z","expires_at":"2027-10-13T10:00:00.000000Z"},
        "instance":{"id":"47596ad9-a811-4ebf-ac8a-03fc7b6d2a17","name":"Mac","created_at":"2026-10-13T10:00:00.000000Z"},
        "meta":{"store_id":1,"order_id":2,"product_id":3,"variant_id":4,"customer_id":5,"customer_name":"A","customer_email":"a@b.c"}}
        """
        let response = try JSONDecoder().decode(LemonSqueezy.Response.self, from: Data(json.utf8))
        let license = try LemonSqueezy.parse(response, requestedKey: "x")
        XCTAssertEqual(license.key, "38b1460a-5104-4067-a91d-77b872934d51")
        XCTAssertEqual(license.email, "a@b.c")
        XCTAssertEqual(license.instanceID, "47596ad9-a811-4ebf-ac8a-03fc7b6d2a17")
        XCTAssertEqual(license.status, "active")
        XCTAssertEqual(license.updatesUntil.map(Licensing.string), "2027-10-13")
    }

    func testRejectsUnknownKeyAndKeepsExpiredOnes() throws {
        let unknown = try JSONDecoder().decode(LemonSqueezy.Response.self, from: Data("""
        {"activated":false,"error":"license_key not found.","license_key":null,"instance":null,"meta":null}
        """.utf8))
        XCTAssertThrowsError(try LemonSqueezy.parse(unknown, requestedKey: "x")) {
            XCTAssertEqual($0 as? LemonSqueezy.Error, .rejected("license_key not found."))
        }
        let expired = try JSONDecoder().decode(LemonSqueezy.Response.self, from: Data("""
        {"valid":false,"error":"This license key has expired.","license_key":{"id":1,"status":"expired","key":"K",
        "expires_at":"2026-01-01T00:00:00.000000Z"},"instance":null,"meta":{"store_id":1,"product_id":3,"customer_email":"a@b.c"}}
        """.utf8))
        let license = try LemonSqueezy.parse(expired, requestedKey: "K")
        XCTAssertEqual(license.status, "expired")
        XCTAssertTrue(try license.covers(buildDate: XCTUnwrap(Licensing.day("2025-12-01"))), "old builds stay covered")
        XCTAssertFalse(try license.covers(buildDate: XCTUnwrap(Licensing.day("2026-02-01"))))
    }

    func testLicenceRoundTripsThroughJSON() throws {
        let k = key(until: "2027-10-13")
        let decoded = try JSONDecoder().decode(LicenseKey.self, from: JSONEncoder().encode(k))
        XCTAssertEqual(decoded, k)
    }
}
