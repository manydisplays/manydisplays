import Carbon
import CoreGraphics
@testable import ManyDisplaysCore
import XCTest

final class SupportTests: XCTestCase {
    func testRectMatchingTolerances() {
        let target = CGRect(x: 100, y: 100, width: 800, height: 600)
        XCTAssertTrue(CGRect(x: 103, y: 97, width: 815, height: 585).matches(target), "position ±4, size ±20")
        XCTAssertFalse(CGRect(x: 105, y: 100, width: 800, height: 600).matches(target))
        XCTAssertFalse(CGRect(x: 100, y: 100, width: 830, height: 600).matches(target))
        XCTAssertTrue(CGRect(x: 102, y: 102, width: 802, height: 598).isClose(to: target))
        XCTAssertFalse(CGRect(x: 104, y: 100, width: 800, height: 600).isClose(to: target))
    }

    func testHotKeyParsing() {
        let spec = HotKeySpec("Ctrl+Alt+Cmd+R")
        XCTAssertEqual(spec?.keyCode, kVK_ANSI_R)
        XCTAssertEqual(spec?.modifiers, controlKey | optionKey | cmdKey)
        XCTAssertEqual(spec?.key, "r")
        XCTAssertEqual(HotKeySpec("shift+f5")?.keyCode, kVK_F5)
        XCTAssertNil(HotKeySpec("r"), "a global shortcut needs a modifier")
        XCTAssertNil(HotKeySpec("ctrl+"), "no key")
        XCTAssertNil(HotKeySpec("hyper+r"), "unknown modifier")
        XCTAssertNil(HotKeySpec("ctrl+enter"), "unsupported key")
        XCTAssertEqual(HotKeySpec("ctrl+alt+cmd+r")?.display, "⌃⌥⌘R")
        XCTAssertEqual(HotKeySpec.text(keyCode: kVK_ANSI_R, flags: [.control, .command]), "ctrl+cmd+r")
        XCTAssertNil(HotKeySpec.text(keyCode: kVK_ANSI_R, flags: [.shift]), "shift alone is not a global shortcut")
        XCTAssertNil(HotKeySpec.text(keyCode: kVK_Return, flags: [.command]), "unsupported key")
    }

    func testLayoutRoundTripsThroughJSON() throws {
        let display = Fixtures.display(key: "lg-1", bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        var layout = Fixtures.layout("lg-1", displays: [display])
        layout.windows["1"] = Fixtures.record(id: 1, title: "Doc")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Layout.self, from: encoder.encode(layout))
        XCTAssertEqual(decoded.windows, layout.windows)
        XCTAssertEqual(decoded.displays, layout.displays)
    }

    func testOldLayoutsWithoutNewerFieldsStillDecode() throws {
        let json = """
        {"profileID":"p","displays":[{"key":"k","name":"n","vendor":1,"model":2,"serial":3,"uuid":"u",
        "isBuiltin":false,"isMain":true,"frame":[[0,0],[100,100]],"pixelWidth":200,"pixelHeight":200}],
        "windows":{},"bootSession":"1","updatedAt":"2026-01-01T00:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let layout = try decoder.decode(Layout.self, from: Data(json.utf8))
        XCTAssertNil(layout.displays[0].refreshRate)
        XCTAssertNil(layout.displays[0].hdr)
    }
}
