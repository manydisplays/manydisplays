import AppKit
import CoreGraphics

struct SpaceTopology {
    /// Every space in Mission Control order (display by display).
    var ordered: [UInt64] = []
    /// 0 = normal desktop, 4 = full-screen app.
    var types: [UInt64: Int] = [:]
    var active: Set<UInt64> = []

    func index(of space: UInt64) -> Int? {
        ordered.firstIndex(of: space)
    }

    func space(at index: Int?) -> UInt64? {
        guard let index, ordered.indices.contains(index) else { return nil }
        return ordered[index]
    }

    var desktopCount: Int {
        types.values.filter { $0 == 0 }.count
    }
}

enum Spaces {
    static let connection = PrivateAPI.CGSMainConnectionID()

    static func topology() -> SpaceTopology {
        var topo = SpaceTopology()
        guard let displays = PrivateAPI.CGSCopyManagedDisplaySpaces(connection) as? [[String: Any]] else { return topo }
        for display in displays {
            if let current = display["Current Space"] as? [String: Any], let id = spaceID(current) {
                topo.active.insert(id)
            }
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                guard let id = spaceID(space) else { continue }
                topo.ordered.append(id)
                topo.types[id] = (space["type"] as? NSNumber)?.intValue ?? 0
            }
        }
        return topo
    }

    static func spaces(for window: CGWindowID) -> [UInt64] {
        let ids = [NSNumber(value: window)] as CFArray
        guard let result = PrivateAPI.CGSCopySpacesForWindows(connection, 0x7, ids) as? [NSNumber] else { return [] }
        return result.map(\.uint64Value)
    }

    private static func spaceID(_ dict: [String: Any]) -> UInt64? {
        ((dict["ManagedSpaceID"] ?? dict["id64"]) as? NSNumber)?.uint64Value
    }
}

struct LiveWindow {
    let id: CGWindowID
    let pid: pid_t
    let ownerName: String
    let title: String?
    let frame: CGRect
    let spaces: [UInt64]
}

struct WindowCapture {
    /// Normal app windows that live in a desktop or full-screen space.
    var trackable: [LiveWindow] = []
    /// Every window id that still exists (any layer, minimized, hidden...). Anything not
    /// in here has been closed and must never come back.
    var existing: Set<CGWindowID> = []
    var byID: [CGWindowID: LiveWindow] = [:]
}

enum WindowList {
    /// System processes whose layer-0 windows are not user windows (menu bar extras, the Dock,
    /// Spotlight, the wallpaper...). Matched by bundle identifier so it works in every language.
    static let excludedBundleIDs: Set<String> = [
        "com.apple.dock", "com.apple.controlcenter", "com.apple.notificationcenterui",
        "com.apple.Spotlight", "com.apple.WindowManager", "com.apple.systemuiserver",
        "com.apple.wallpaper.agent", "com.apple.loginwindow", "com.apple.screencaptureui",
        "com.apple.TextInputMenuAgent", "com.apple.PowerChime", "com.apple.UniversalControl",
    ]
    /// Fallback for processes without a bundle (the window server itself).
    private static let excludedOwners: Set<String> = ["Window Server", "WindowServer"]

    /// One CGWindowList call plus one tiny space query per normal window. ~10-30 ms for
    /// hundreds of windows, no Accessibility round-trips, so it can run often.
    static func capture(topology: SpaceTopology, ownPID: pid_t, apps: AppInfoCache) -> WindowCapture {
        var result = WindowCapture()
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return result }

        for info in list {
            guard let number = info[kCGWindowNumber as String] as? NSNumber else { continue }
            let id = number.uint32Value
            result.existing.insert(id)

            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != ownPID,
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0.01,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict),
                  frame.width >= Tuning.minimumWindowSide, frame.height >= Tuning.minimumWindowSide
            else { continue }

            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            if excludedOwners.contains(owner) {
                continue
            }
            if let bundleID = apps.info(pid).bundleID, excludedBundleIDs.contains(bundleID) {
                continue
            }

            let spaces = Spaces.spaces(for: id).filter { topology.types[$0] != nil }
            if spaces.isEmpty {
                continue
            }

            let title = (info[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let window = LiveWindow(id: id, pid: pid, ownerName: owner, title: title, frame: frame, spaces: spaces)
            result.trackable.append(window)
            result.byID[id] = window
        }
        return result
    }
}

/// Small pid -> app metadata cache (only touched from the engine queue).
final class AppInfoCache {
    struct Info {
        let bundleID: String?
        let name: String?
    }

    private var cache: [pid_t: Info] = [:]

    func info(_ pid: pid_t) -> Info {
        if let hit = cache[pid] {
            return hit
        }
        let app = NSRunningApplication(processIdentifier: pid)
        let info = Info(bundleID: app?.bundleIdentifier, name: app?.localizedName)
        if cache.count > 400 {
            cache.removeAll()
        }
        cache[pid] = info
        return info
    }
}
