import CoreGraphics
import Foundation

/// Pure functions of the engine, kept free of state so they can be unit-tested.
enum LayoutMath {
    /// Where a saved window belongs on the display as it is now. If the display changed
    /// resolution since the layout was saved, the frame is scaled proportionally and kept inside.
    static func targetFrame(_ record: WindowRecord, saved: DisplayInfo?, current: LiveDisplay) -> CGRect {
        var rel = record.relFrame
        let bounds = current.bounds
        if let saved, saved.frame.size != bounds.size, saved.frame.width > 0, saved.frame.height > 0 {
            let sx = bounds.width / saved.frame.width
            let sy = bounds.height / saved.frame.height
            rel = CGRect(x: rel.minX * sx, y: rel.minY * sy, width: rel.width * sx, height: rel.height * sy)
            rel.size.width = min(rel.width, bounds.width)
            rel.size.height = min(rel.height, bounds.height)
            rel.origin.x = min(max(rel.minX, 0), bounds.width - rel.width)
            rel.origin.y = min(max(rel.minY, 0), bounds.height - rel.height)
        }
        return rel.offsetBy(dx: bounds.minX, dy: bounds.minY).integral
    }

    /// For a display combination never seen before (e.g. the same monitors but with the lid
    /// open), the layout that shares the most external monitors; ties go to the most recent.
    static func closestLayout(to displays: [LiveDisplay], among layouts: [Layout]) -> Layout? {
        let external = Set(displays.filter { !$0.isBuiltin }.map(\.key))
        return layouts
            .map { layout -> (Layout, Int) in
                (layout, Set(layout.displays.filter { !$0.isBuiltin }.map(\.key)).intersection(external).count)
            }
            .filter { $0.1 > 0 }
            .max { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.updatedAt < $1.0.updatedAt }?
            .0
    }

    /// After a reboot or an app relaunch the window ids change. Pairs saved records whose
    /// window is gone with new windows of the same app: by title, or when the app has exactly
    /// one new window and exactly one dead record.
    static func rebind(
        dead: [WindowRecord],
        candidates: [String: [LiveWindow]],
        titles: [CGWindowID: String]
    ) -> [(record: WindowRecord, window: LiveWindow)] {
        var candidates = candidates
        let deadPerBundle = Dictionary(grouping: dead, by: { $0.bundleID ?? "" }).mapValues(\.count)
        var pairs: [(WindowRecord, LiveWindow)] = []
        // Titled records first, so the "single window" fallback never steals a titled match.
        for record in dead.sorted(by: { ($0.title ?? "") > ($1.title ?? "") }) {
            guard let bundle = record.bundleID, var list = candidates[bundle], !list.isEmpty else { continue }
            var index: Int?
            if let title = record.title {
                index = list.firstIndex { ($0.title ?? titles[$0.id]) == title }
            }
            if index == nil, list.count == 1, deadPerBundle[bundle] == 1 {
                index = 0
            }
            guard let i = index else { continue }
            let window = list.remove(at: i)
            candidates[bundle] = list
            pairs.append((record, window))
        }
        return pairs
    }
}
