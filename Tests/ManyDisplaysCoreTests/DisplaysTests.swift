import CoreGraphics
@testable import ManyDisplaysCore
import XCTest

final class DisplaysTests: XCTestCase {
    let left = Fixtures.display(key: "lg-1", bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080), id: 1)
    let right = Fixtures.display(key: "lg-2", bounds: CGRect(x: 1920, y: 0, width: 1920, height: 1080), id: 2)

    func testProfileIDIsOrderIndependent() {
        XCTAssertEqual(Displays.profileID([left, right]), Displays.profileID([right, left]))
        XCTAssertEqual(Displays.profileID([left, right]), "lg-1+lg-2")
    }

    func testBestDisplayIsTheOneWithMostOverlapOrNearest() {
        let straddling = CGRect(x: 1500, y: 100, width: 1000, height: 500) // 420 px on the left, 580 on the right
        XCTAssertEqual(Displays.best(for: straddling, in: [left, right])?.key, "lg-2")
        let offscreen = CGRect(x: -5000, y: 100, width: 300, height: 300)
        XCTAssertEqual(Displays.best(for: offscreen, in: [left, right])?.key, "lg-1")
        XCTAssertNil(Displays.best(for: offscreen, in: []))
    }

    func testConfigurationFixDetectsSwappedArrangement() {
        let saved = [DisplayInfo(left), DisplayInfo(right)]
        let swappedLeft = Fixtures.display(key: "lg-1", bounds: right.bounds, id: 1)
        let swappedRight = Fixtures.display(key: "lg-2", bounds: left.bounds, id: 2)
        let fix = Displays.configurationFix(saved: saved, current: [swappedLeft, swappedRight])
        XCTAssertEqual(fix?.arrangementChanged, true)
        XCTAssertEqual(fix?.origins["lg-1"], .zero)
        XCTAssertEqual(fix?.origins["lg-2"], CGPoint(x: 1920, y: 0))
        XCTAssertNil(Displays.configurationFix(saved: saved, current: [left, right]), "nothing to fix")
        XCTAssertNil(Displays.configurationFix(saved: saved, current: [left]), "different set of displays")
    }

    func testRotationFixOnlyForSameDisplaySet() {
        var saved = DisplayInfo(left)
        saved.rotation = 90
        XCTAssertEqual(Displays.rotationFix(saved: [saved, DisplayInfo(right)], current: [left, right]), [1: 90])
        XCTAssertEqual(Displays.rotationFix(saved: [saved], current: [left, right]), [:])
    }

    func testSpaceTopologyIndexing() {
        var topo = SpaceTopology()
        topo.ordered = [10, 11, 12]
        topo.types = [10: 0, 11: 0, 12: 4]
        XCTAssertEqual(topo.index(of: 11), 1)
        XCTAssertEqual(topo.space(at: 2), 12)
        XCTAssertNil(topo.space(at: 3))
        XCTAssertNil(topo.space(at: nil))
        XCTAssertEqual(topo.desktopCount, 2)
    }
}
