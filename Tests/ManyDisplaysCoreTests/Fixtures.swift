import CoreGraphics
import Foundation
@testable import ManyDisplaysCore

enum Fixtures {
    static func display(key: String, bounds: CGRect, builtin: Bool = false, id: CGDirectDisplayID = 1) -> LiveDisplay {
        LiveDisplay(
            id: id,
            key: key,
            name: key,
            vendor: 0,
            model: 0,
            serial: 0,
            uuid: "",
            isBuiltin: builtin,
            isMain: bounds.origin == .zero,
            bounds: bounds,
            pixelWidth: Int(bounds.width) * 2,
            pixelHeight: Int(bounds.height) * 2,
            refreshRate: 60,
            modeID: 1,
            rotation: 0,
            mirrorOf: kCGNullDirectDisplay
        )
    }

    static func record(
        id: CGWindowID,
        bundle: String? = "com.example.app",
        title: String? = nil,
        display: String = "left",
        frame: CGRect = CGRect(x: 10, y: 20, width: 800, height: 600)
    ) -> WindowRecord {
        WindowRecord(
            windowID: id,
            pid: 100,
            bundleID: bundle,
            appName: "App",
            title: title,
            displayKey: display,
            relFrame: frame,
            spaceID: nil,
            spaceIndex: nil,
            onAllSpaces: false,
            fullscreen: false
        )
    }

    static func window(id: CGWindowID, pid: pid_t = 200, title: String? = nil) -> LiveWindow {
        LiveWindow(
            id: id,
            pid: pid,
            ownerName: "App",
            title: title,
            frame: CGRect(x: 0, y: 0, width: 500, height: 400),
            spaces: [1]
        )
    }

    static func layout(_ profile: String, displays: [LiveDisplay], updatedAt: Date = Date()) -> Layout {
        var layout = Layout(profileID: profile)
        layout.displays = displays.map { DisplayInfo($0) }
        layout.updatedAt = updatedAt
        return layout
    }
}
