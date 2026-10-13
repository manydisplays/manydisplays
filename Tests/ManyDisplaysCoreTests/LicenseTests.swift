import CryptoKit
import Foundation
@testable import ManyDisplaysCore
import XCTest

final class LicenseTests: XCTestCase {
    let signing = Curve25519.Signing.PrivateKey()
    var publicKey: Data {
        signing.publicKey.rawRepresentation
    }

    let day = Licensing.day

    func issue(email: String = "a@b.c", until: String = "2027-10-13") throws -> String {
        try LicenseKey.issue(
            email: email,
            issuedAt: day("2026-10-13")!,
            updatesUntil: day(until)!,
            privateKey: signing.rawRepresentation
        )
    }

    func testIssuedKeysVerifyAndCarryTheirFields() throws {
        let text = try issue()
        XCTAssertTrue(text.hasPrefix("MD1."))
        let key = try LicenseKey.verify(" \(text)\n", publicKey: publicKey)
        XCTAssertEqual(key.email, "a@b.c")
        XCTAssertEqual(Licensing.string(key.issuedAt), "2026-10-13")
        XCTAssertEqual(Licensing.string(key.updatesUntil), "2027-10-13")
        XCTAssertEqual(key.text, text)
    }

    func testTamperedOrForeignKeysAreRejected() throws {
        let text = try issue()
        let other = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
        XCTAssertThrowsError(try LicenseKey.verify(text, publicKey: other)) { XCTAssertEqual(
            $0 as? LicenseKey.Error,
            .badSignature
        ) }
        let parts = text.split(separator: ".")
        let forgedPayload = Data("x@y.z|2026-10-13|2099-01-01".utf8).base64URL
        XCTAssertThrowsError(try LicenseKey.verify("MD1.\(forgedPayload).\(parts[2])", publicKey: publicKey)) {
            XCTAssertEqual($0 as? LicenseKey.Error, .badSignature)
        }
        XCTAssertThrowsError(try LicenseKey.verify("hello", publicKey: publicKey)) { XCTAssertEqual(
            $0 as? LicenseKey.Error,
            .malformed
        ) }
        XCTAssertThrowsError(try LicenseKey.verify("MD2.\(parts[1]).\(parts[2])", publicKey: publicKey)) { XCTAssertEqual(
            $0 as? LicenseKey.Error,
            .malformed
        ) }
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
        let key = try LicenseKey.verify(issue(until: "2027-10-13"), publicKey: publicKey)
        XCTAssertEqual(
            try LicenseState
                .compute(required: true, key: key, trialStartedAt: .distantPast, buildDate: XCTUnwrap(day("2027-10-13"))),
            .licensed(key)
        )
        XCTAssertEqual(
            try LicenseState
                .compute(required: true, key: key, trialStartedAt: .distantPast, buildDate: XCTUnwrap(day("2027-10-14"))),
            .updatesExpired(key)
        )
        XCTAssertFalse(LicenseState.updatesExpired(key).allowsRestoring)
    }

    func testShopPublicKeyIsWellFormed() {
        XCTAssertEqual(Licensing.publicKey.count, 32)
        XCTAssertNoThrow(try Curve25519.Signing.PublicKey(rawRepresentation: Licensing.publicKey))
    }
}
