import CoreGraphics
@testable import ManyDisplaysCore
import XCTest

final class LayoutMathTests: XCTestCase {
    func testTargetFrameOffsetsByDisplayOrigin() {
        let display = Fixtures.display(key: "right", bounds: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        let record = Fixtures.record(id: 1, display: "right", frame: CGRect(x: 10, y: 20, width: 800, height: 600))
        let target = LayoutMath.targetFrame(record, saved: DisplayInfo(display), current: display)
        XCTAssertEqual(target, CGRect(x: 1930, y: 20, width: 800, height: 600))
    }

    func testTargetFrameScalesWhenResolutionChanged() {
        let saved = Fixtures.display(key: "a", bounds: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        let current = Fixtures.display(key: "a", bounds: CGRect(x: 0, y: 0, width: 2000, height: 500))
        let record = Fixtures.record(id: 1, display: "a", frame: CGRect(x: 100, y: 100, width: 400, height: 400))
        let target = LayoutMath.targetFrame(record, saved: DisplayInfo(saved), current: current)
        XCTAssertEqual(target, CGRect(x: 200, y: 50, width: 800, height: 200))
    }

    func testTargetFrameStaysInsideSmallerDisplay() {
        let saved = Fixtures.display(key: "a", bounds: CGRect(x: 0, y: 0, width: 2000, height: 2000))
        let current = Fixtures.display(key: "a", bounds: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        let record = Fixtures.record(id: 1, display: "a", frame: CGRect(x: 1500, y: 1500, width: 1000, height: 1000))
        let target = LayoutMath.targetFrame(record, saved: DisplayInfo(saved), current: current)
        XCTAssertEqual(target, CGRect(x: 500, y: 500, width: 500, height: 500))
        XCTAssertTrue(current.bounds.contains(target))
    }

    func testClosestLayoutPrefersMostSharedExternalMonitorsThenRecency() {
        let left = Fixtures.display(key: "lg-1", bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let right = Fixtures.display(key: "lg-2", bounds: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        let builtin = Fixtures.display(key: "builtin", bounds: CGRect(x: 0, y: 1080, width: 1512, height: 982), builtin: true)
        let other = Fixtures.display(key: "dell", bounds: .zero)

        let old = Fixtures.layout("both-old", displays: [left, right], updatedAt: Date(timeIntervalSince1970: 1))
        let recent = Fixtures.layout("both-recent", displays: [left, right], updatedAt: Date(timeIntervalSince1970: 2))
        let one = Fixtures.layout("one", displays: [left, builtin], updatedAt: Date(timeIntervalSince1970: 3))
        let unrelated = Fixtures.layout("unrelated", displays: [other], updatedAt: Date(timeIntervalSince1970: 4))

        let closest = LayoutMath.closestLayout(to: [left, right, builtin], among: [old, recent, one, unrelated])
        XCTAssertEqual(closest?.profileID, "both-recent")
        XCTAssertNil(LayoutMath.closestLayout(to: [other], among: [old, one]))
        XCTAssertNil(LayoutMath.closestLayout(to: [builtin], among: [one]), "built-in panels never count as shared")
    }

    func testRebindMatchesByTitleBeforeSingleWindowFallback() {
        let titled = Fixtures.record(id: 1, title: "Budget.xlsx")
        let untitled = Fixtures.record(id: 2, bundle: "com.example.other")
        let candidates: [String: [LiveWindow]] = [
            "com.example.app": [Fixtures.window(id: 11, title: "Notes"), Fixtures.window(id: 12)],
            "com.example.other": [Fixtures.window(id: 21)],
        ]
        let pairs = LayoutMath.rebind(dead: [titled, untitled], candidates: candidates, titles: [12: "Budget.xlsx"])
        let byRecord = Dictionary(uniqueKeysWithValues: pairs.map { ($0.record.windowID, $0.window.id) })
        XCTAssertEqual(byRecord[1], 12, "matched through the AX title")
        XCTAssertEqual(byRecord[2], 21, "only window of an app with one dead record")
    }

    func testRebindNeverGuessesAmongSeveralWindows() {
        let a = Fixtures.record(id: 1)
        let b = Fixtures.record(id: 2)
        let candidates = ["com.example.app": [Fixtures.window(id: 11), Fixtures.window(id: 12)]]
        XCTAssertTrue(LayoutMath.rebind(dead: [a, b], candidates: candidates, titles: [:]).isEmpty)
    }
}
