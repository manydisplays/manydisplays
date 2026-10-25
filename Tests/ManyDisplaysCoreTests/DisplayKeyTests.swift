import CoreGraphics
@testable import ManyDisplaysCore
import XCTest

/// Display keys are stored in saved layouts: these pin down that each case keeps its key.
final class DisplayKeyTests: XCTestCase {
    let base = "1e6d-7707-00000000"
    let left = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let right = CGRect(x: 1920, y: 0, width: 1920, height: 1080)

    func hw(_ port: Int, _ made: String?) -> DisplayPorts.Hardware {
        DisplayPorts.Hardware(port: port, manufactured: made)
    }

    func testDifferentUUIDsKeepUUIDKeysEvenWithPortsAndDates() {
        let keys = Displays.disambiguate(
            base: base,
            [.init(id: 1, uuid: "AAAAAAAA-1", bounds: left), .init(id: 2, uuid: "BBBBBBBB-2", bounds: right)],
            hardware: [1: hw(0, "2019w04"), 2: hw(16, "2022w04")]
        )
        XCTAssertEqual(keys, [1: "\(base)-AAAAAAAA", 2: "\(base)-BBBBBBBB"])
    }

    func testDistinctPortsKeepPortKeysEvenWhenDatesDiffer() {
        let keys = Displays.disambiguate(
            base: base,
            [.init(id: 1, uuid: "SAME", bounds: left), .init(id: 2, uuid: "SAME", bounds: right)],
            hardware: [1: hw(0, "2019w04"), 2: hw(16, "2022w04")]
        )
        XCTAssertEqual(keys, [1: "\(base)-port0", 2: "\(base)-port16"])
    }

    func testSamePortUsesManufactureDate() {
        let keys = Displays.disambiguate(
            base: base,
            [.init(id: 1, uuid: "SAME", bounds: right), .init(id: 2, uuid: "SAME", bounds: left)],
            hardware: [1: hw(0, "2019w04"), 2: hw(0, "2022w04")]
        )
        XCTAssertEqual(keys, [1: "\(base)-made2019w04", 2: "\(base)-made2022w04"])
    }

    func testSamePortAndSameDateFallBackToPosition() {
        let keys = Displays.disambiguate(
            base: base,
            [.init(id: 1, uuid: "SAME", bounds: right), .init(id: 2, uuid: "SAME", bounds: left)],
            hardware: [1: hw(0, "2022w04"), 2: hw(0, "2022w04")]
        )
        XCTAssertEqual(keys, [1: "\(base)-SAME-pos1", 2: "\(base)-SAME-pos0"])
    }

    func testMissingHardwareFallsBackToPosition() {
        let keys = Displays.disambiguate(
            base: base,
            [.init(id: 1, uuid: "SAME", bounds: left), .init(id: 2, uuid: "SAME", bounds: right)],
            hardware: [1: hw(0, nil)]
        )
        XCTAssertEqual(keys, [1: "\(base)-SAME-pos0", 2: "\(base)-SAME-pos1"])
    }
}
