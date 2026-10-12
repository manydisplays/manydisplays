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

    init(_ d: LiveDisplay) {
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
    }
}

enum Displays {
    static func current() -> [LiveDisplay] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }

        struct Raw {
            let id: CGDirectDisplayID
            let base: String
            let uuid: String
        }
        var raws: [Raw] = []
        for id in ids.prefix(Int(count)) {
            // Mirrored secondaries are not separate places for windows.
            if CGDisplayMirrorsDisplay(id) != kCGNullDirectDisplay { continue }
            let uuid = CGDisplayCreateUUIDFromDisplayID(id).map {
                CFUUIDCreateString(nil, $0.takeRetainedValue()) as String
            } ?? ""
            let base: String
            if CGDisplayIsBuiltin(id) != 0 {
                base = "builtin"
            } else {
                base = String(format: "%04x-%04x-%08x",
                              CGDisplayVendorNumber(id), CGDisplayModelNumber(id), CGDisplaySerialNumber(id))
            }
            raws.append(Raw(id: id, base: base, uuid: uuid))
        }

        // Identical monitors can report the same vendor/model/serial (often serial 0 or 0x01010101).
        // Disambiguate with the system UUID, and as a last resort with the left-to-right position.
        var keys: [CGDirectDisplayID: String] = [:]
        for (base, group) in Dictionary(grouping: raws, by: \.base) {
            if group.count == 1 {
                keys[group[0].id] = base
                continue
            }
            for (uuid, sub) in Dictionary(grouping: group, by: \.uuid) {
                if sub.count == 1 {
                    keys[sub[0].id] = "\(base)-\(uuid.prefix(8))"
                } else {
                    let ordered = sub.sorted {
                        let a = CGDisplayBounds($0.id), b = CGDisplayBounds($1.id)
                        return a.minX != b.minX ? a.minX < b.minX : a.minY < b.minY
                    }
                    for (i, r) in ordered.enumerated() { keys[r.id] = "\(base)-\(uuid.prefix(8))-pos\(i)" }
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
                pixelHeight: mode?.pixelHeight ?? 0
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
        if best != nil { return best }
        let c = CGPoint(x: rect.midX, y: rect.midY)
        return displays.min {
            hypot($0.bounds.midX - c.x, $0.bounds.midY - c.y) < hypot($1.bounds.midX - c.x, $1.bounds.midY - c.y)
        }
    }

    /// When macOS wakes up with the same monitors but swaps their arrangement (the classic
    /// identical-monitor bug), returns the saved origins to put them back. Nil if nothing to fix
    /// or if the situation is not a pure swap (different set of displays or resolutions).
    static func arrangementFix(saved: [DisplayInfo], current: [LiveDisplay]) -> [String: CGPoint]? {
        guard current.count >= 2, Set(saved.map(\.key)) == Set(current.map(\.key)) else { return nil }
        let savedByKey = Dictionary(saved.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var differs = false
        var origins: [String: CGPoint] = [:]
        for d in current {
            guard let s = savedByKey[d.key], s.frame.size == d.bounds.size else { return nil }
            if s.frame.origin != d.bounds.origin { differs = true }
            origins[d.key] = s.frame.origin
        }
        guard differs, origins.values.contains(.zero) else { return nil }
        return origins
    }

    static func applyArrangement(_ origins: [String: CGPoint], current: [LiveDisplay]) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        for d in current {
            guard let p = origins[d.key] else { continue }
            CGConfigureDisplayOrigin(config, d.id, Int32(p.x), Int32(p.y))
        }
        let err = CGCompleteDisplayConfiguration(config, .permanently)
        if err != .success {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return true
    }
}
