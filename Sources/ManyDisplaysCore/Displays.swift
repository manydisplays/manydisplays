import ColorSync
import CoreGraphics
import Foundation

/// A display as it is connected right now. Coordinates are global CG coordinates
/// (origin at the top-left of the main display, y grows downwards), the same space
/// used by CGWindowList and the Accessibility API.
struct LiveDisplay {
    let id: CGDirectDisplayID
    let key: String
    let name: String
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32
    let uuid: String
    let isBuiltin: Bool
    let isMain: Bool
    let bounds: CGRect
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
    let modeID: Int32
    let rotation: Int
    /// Display it mirrors, or kCGNullDirectDisplay.
    let mirrorOf: CGDirectDisplayID
}

/// What we persist about a display inside a layout.
struct DisplayInfo: Codable, Equatable {
    var key: String
    var name: String
    var vendor: UInt32
    var model: UInt32
    var serial: UInt32
    var uuid: String
    var isBuiltin: Bool
    var isMain: Bool
    var frame: CGRect
    var pixelWidth: Int
    var pixelHeight: Int
    // Optional so layouts saved by older builds still decode.
    var refreshRate: Double?
    var modeID: Int32?
    var rotation: Int?
    /// Only set for displays that support HDR.
    var hdr: Bool?

    init(_ d: LiveDisplay, hdr: Bool? = nil) {
        key = d.key
        name = d.name
        vendor = d.vendor
        model = d.model
        serial = d.serial
        uuid = d.uuid
        isBuiltin = d.isBuiltin
        isMain = d.isMain
        frame = d.bounds
        pixelWidth = d.pixelWidth
        pixelHeight = d.pixelHeight
        refreshRate = d.refreshRate
        modeID = d.modeID
        rotation = d.rotation
        self.hdr = hdr
    }
}

enum Displays {
    /// Displays that can hold windows (mirrored secondaries excluded).
    static func current() -> [LiveDisplay] {
        all().filter { $0.mirrorOf == kCGNullDirectDisplay }
    }

    /// Every active display, including the secondaries of a mirror set.
    static func all() -> [LiveDisplay] {
        /// Active displays (drawable; sleeping ones are excluded), plus online mirror secondaries
        /// in case they are not listed.
        func list(_ fetch: (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError)
            -> [CGDirectDisplayID] {
            var count: UInt32 = 0
            guard fetch(0, nil, &count) == .success, count > 0 else { return [] }
            var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
            guard fetch(count, &ids, &count) == .success else { return [] }
            return Array(ids.prefix(Int(count)))
        }
        var active = list(CGGetActiveDisplayList)
        for id in list(CGGetOnlineDisplayList)
            where !active.contains(id) && CGDisplayMirrorsDisplay(id) != kCGNullDirectDisplay {
            active.append(id)
        }

        struct Raw {
            let id: CGDirectDisplayID
            let base: String
            let uuid: String
        }
        var raws: [Raw] = []
        for id in active {
            let uuid = CGDisplayCreateUUIDFromDisplayID(id).map {
                CFUUIDCreateString(nil, $0.takeRetainedValue()) as String
            } ?? ""
            let base = if CGDisplayIsBuiltin(id) != 0 {
                "builtin"
            } else {
                String(
                    format: "%04x-%04x-%08x",
                    CGDisplayVendorNumber(id),
                    CGDisplayModelNumber(id),
                    CGDisplaySerialNumber(id)
                )
            }
            raws.append(Raw(id: id, base: base, uuid: uuid))
        }

        // Identical monitors can report the same vendor/model/serial (often serial 0 or 0x01010101).
        // Disambiguate with the system UUID, then with the physical port they are plugged into,
        // and as a last resort with the left-to-right position.
        var keys: [CGDirectDisplayID: String] = [:]
        var ports: [CGDirectDisplayID: Int]?
        for (base, group) in Dictionary(grouping: raws, by: \.base) {
            if group.count == 1 {
                keys[group[0].id] = base
                continue
            }
            for (uuid, sub) in Dictionary(grouping: group, by: \.uuid) {
                if sub.count == 1 {
                    keys[sub[0].id] = "\(base)-\(uuid.prefix(8))"
                    continue
                }
                if ports == nil {
                    ports = DisplayPorts.portIDs(for: raws.map(\.id))
                }
                let subPorts = sub.compactMap { ports?[$0.id] }
                if subPorts.count == sub.count, Set(subPorts).count == sub.count {
                    for r in sub {
                        keys[r.id] = "\(base)-port\(ports![r.id]!)"
                    }
                    continue
                }
                let ordered = sub.sorted {
                    let a = CGDisplayBounds($0.id), b = CGDisplayBounds($1.id)
                    return a.minX != b.minX ? a.minX < b.minX : a.minY < b.minY
                }
                for (i, r) in ordered.enumerated() {
                    keys[r.id] = "\(base)-\(uuid.prefix(8))-pos\(i)"
                }
            }
        }

        return raws.map { r in
            let mode = CGDisplayCopyDisplayMode(r.id)
            let builtin = CGDisplayIsBuiltin(r.id) != 0
            return LiveDisplay(
                id: r.id,
                key: keys[r.id] ?? r.base,
                name: DisplayNames.name(for: r.id) ?? (builtin ? "Built-in Display" : "Display \(r.id)"),
                vendor: CGDisplayVendorNumber(r.id),
                model: CGDisplayModelNumber(r.id),
                serial: CGDisplaySerialNumber(r.id),
                uuid: r.uuid,
                isBuiltin: builtin,
                isMain: CGDisplayIsMain(r.id) != 0,
                bounds: CGDisplayBounds(r.id),
                pixelWidth: mode?.pixelWidth ?? 0,
                pixelHeight: mode?.pixelHeight ?? 0,
                refreshRate: mode?.refreshRate ?? 0,
                modeID: mode?.ioDisplayModeID ?? 0,
                rotation: Int(CGDisplayRotation(r.id).rounded()),
                mirrorOf: CGDisplayMirrorsDisplay(r.id)
            )
        }
    }

    static func hasExternal(_ displays: [LiveDisplay]) -> Bool {
        displays.contains { !$0.isBuiltin }
    }

    /// Identifies the combination of physical displays (not their resolution or arrangement).
    static func profileID(_ displays: [LiveDisplay]) -> String {
        displays.map(\.key).sorted().joined(separator: "+")
    }

    static func profileName(_ displays: [DisplayInfo]) -> String {
        let sorted = displays.sorted { $0.frame.minX < $1.frame.minX }
        return sorted.map { "\($0.name) \(Int($0.frame.width))×\(Int($0.frame.height))" }.joined(separator: " · ")
    }

    /// The display that contains most of the rect.
    static func best(for rect: CGRect, in displays: [LiveDisplay]) -> LiveDisplay? {
        var best: LiveDisplay?
        var bestArea: CGFloat = 0
        for d in displays {
            let i = d.bounds.intersection(rect)
            let area = i.isNull ? 0 : i.width * i.height
            if area > bestArea {
                bestArea = area
                best = d
            }
        }
        if best != nil {
            return best
        }
        let c = CGPoint(x: rect.midX, y: rect.midY)
        return displays.min {
            hypot($0.bounds.midX - c.x, $0.bounds.midY - c.y) < hypot($1.bounds.midX - c.x, $1.bounds.midY - c.y)
        }
    }

    struct ConfigurationFix {
        var origins: [String: CGPoint] = [:]
        var modes: [String: CGDisplayMode] = [:]
        var arrangementChanged = false
    }

    /// After waking up or reconnecting with the same monitors, macOS sometimes swaps the
    /// arrangement of identical monitors (left/right or the main display) and/or forgets their
    /// resolution or refresh rate. Returns what to change to get back to the saved setup, or nil
    /// if it already matches (or the set of displays is different).
    static func configurationFix(saved: [DisplayInfo], current: [LiveDisplay]) -> ConfigurationFix? {
        guard !current.isEmpty, Set(saved.map(\.key)) == Set(current.map(\.key)) else { return nil }
        let savedByKey = Dictionary(saved.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var fix = ConfigurationFix()
        for d in current {
            guard let s = savedByKey[d.key] else { return nil }
            fix.origins[d.key] = s.frame.origin
            if current.count >= 2, s.frame.origin != d.bounds.origin {
                fix.arrangementChanged = true
            }
            if let rotation = s.rotation, rotation != d.rotation {
                continue
            } // fixed in an earlier step
            let sameMode = s.frame.size == d.bounds.size && s.pixelWidth == d.pixelWidth
                && s.pixelHeight == d.pixelHeight
                && (s.refreshRate.map { abs($0 - d.refreshRate) < 0.5 } ?? true)
            if !sameMode, let mode = matchingMode(for: s, on: d.id) {
                fix.modes[d.key] = mode
            }
        }
        guard fix.arrangementChanged || !fix.modes.isEmpty, fix.origins.values.contains(.zero) else { return nil }
        return fix
    }

    private static func matchingMode(for saved: DisplayInfo, on display: CGDirectDisplayID) -> CGDisplayMode? {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode] else { return nil }
        let candidates = modes.filter {
            $0.width == Int(saved.frame.width) && $0.height == Int(saved.frame.height)
                && $0.pixelWidth == saved.pixelWidth && $0.pixelHeight == saved.pixelHeight
        }
        if let id = saved.modeID, let exact = candidates.first(where: { $0.ioDisplayModeID == id }) {
            return exact
        }
        if let rate = saved.refreshRate {
            return candidates.min { abs($0.refreshRate - rate) < abs($1.refreshRate - rate) }
        }
        return candidates.first
    }

    /// Displays whose rotation differs from the saved one (degrees to restore).
    static func rotationFix(saved: [DisplayInfo], current: [LiveDisplay]) -> [CGDirectDisplayID: Int] {
        guard Set(saved.map(\.key)) == Set(current.map(\.key)) else { return [:] }
        let savedByKey = Dictionary(saved.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var result: [CGDirectDisplayID: Int] = [:]
        for d in current {
            if let rotation = savedByKey[d.key]?.rotation, rotation != d.rotation {
                result[d.id] = rotation
            }
        }
        return result
    }

    /// Displays whose HDR setting differs from the saved one.
    static func hdrFix(saved: [DisplayInfo], current: [LiveDisplay]) -> [CGDirectDisplayID: Bool] {
        guard Set(saved.map(\.key)) == Set(current.map(\.key)) else { return [:] }
        let savedHDR = Dictionary(saved.compactMap { d in d.hdr.map { (d.key, $0) } }, uniquingKeysWith: { a, _ in a })
        guard !savedHDR.isEmpty else { return [:] }
        let live = DisplayPanel.hdrStates()
        var result: [CGDirectDisplayID: Bool] = [:]
        for d in current {
            if let want = savedHDR[d.key], let now = live[d.id], want != now {
                result[d.id] = want
            }
        }
        return result
    }

    static func unmirror(_ ids: [CGDirectDisplayID]) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        for id in ids {
            CGConfigureDisplayMirrorOfDisplay(config, id, kCGNullDirectDisplay)
        }
        if CGCompleteDisplayConfiguration(config, .permanently) != .success {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return true
    }

    static func apply(_ fix: ConfigurationFix, current: [LiveDisplay]) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        for d in current {
            if let mode = fix.modes[d.key] {
                CGConfigureDisplayWithDisplayMode(config, d.id, mode, nil)
            }
            if fix.arrangementChanged, let p = fix.origins[d.key] {
                CGConfigureDisplayOrigin(config, d.id, Int32(p.x), Int32(p.y))
            }
        }
        let err = CGCompleteDisplayConfiguration(config, .permanently)
        if err != .success {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return true
    }
}
