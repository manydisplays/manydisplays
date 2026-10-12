import AppKit

/// `ManyDisplays --dump`: prints what the app sees, plus a dry run of a restore.
enum Diagnostics {
    static func dump() {
        DisplayNames.refresh()
        let displays = Displays.current()
        print("== Displays (\(displays.count))  profile: \(Displays.profileID(displays))")
        for d in displays {
            print("  \(d.key)  \(d.name)  id=\(d.id) main=\(d.isMain) builtin=\(d.isBuiltin) bounds=\(d.bounds) px=\(d.pixelWidth)x\(d.pixelHeight)@\(Int(d.refreshRate))Hz mode=\(d.modeID) rot=\(d.rotation) serial=\(d.serial) uuid=\(d.uuid)")
        }

        let ports = DisplayPorts.portIDs(for: Displays.all().map(\.id))
        let hdr = DisplayPanel.hdrStates()
        for d in Displays.all() {
            print("  \(d.key): port=\(ports[d.id].map(String.init) ?? "-") hdr=\(hdr[d.id].map { "\($0)" } ?? "n/a") mirrorOf=\(d.mirrorOf)")
        }

        let topology = Spaces.topology()
        print("== Spaces: \(topology.ordered.count) (\(topology.desktopCount) desktops), active: \(topology.active)")

        let start = Date()
        let capture = WindowList.capture(topology: topology, ownPID: getpid())
        let ms = Date().timeIntervalSince(start) * 1000
        print("== Windows: \(capture.trackable.count) trackable of \(capture.existing.count) (capture \(String(format: "%.1f", ms)) ms)")
        for w in capture.trackable.sorted(by: { $0.ownerName < $1.ownerName }) {
            let display = Displays.best(for: w.frame, in: displays)?.key ?? "?"
            let spaces = w.spaces.map { topology.index(of: $0).map { "#\($0 + 1)" } ?? "?" }.joined(separator: ",")
            print("  \(w.id)  \(w.ownerName)  \(w.title ?? "")  \(w.frame)  monitor=\(display)  space=\(spaces)")
        }

        if AX.isTrusted {
            // Can we reach windows that live in other desktops (needed to restore them without visiting)?
            let offSpace = capture.trackable.filter { Set($0.spaces).isDisjoint(with: topology.active) }
            var reached = 0
            let t0 = Date()
            for (pid, windows) in Dictionary(grouping: offSpace, by: \.pid) {
                let t = Date()
                let found = AX.elements(pid: pid, wanted: Set(windows.map(\.id)), deep: true)
                reached += found.count
                let missing = windows.filter { found[$0.id] == nil }.map { "\($0.id) \(Int($0.frame.width))x\(Int($0.frame.height))" }
                print("   \(windows[0].ownerName): \(found.count)/\(windows.count) \(Int(Date().timeIntervalSince(t) * 1000)) ms  missing: \(missing)")
            }
            print("== AX: \(reached)/\(offSpace.count) windows on other Spaces reachable (\(Int(Date().timeIntervalSince(t0) * 1000)) ms)")
        } else {
            print("== AX: no Accessibility permission")
        }

        let store = LayoutStore()
        let profile = Displays.profileID(displays)
        print("== Saved: \(store.layouts.count) display setups")
        for layout in store.layouts.values {
            print("  \(layout.profileID == profile ? "*" : " ") \(Displays.profileName(layout.displays))  \(layout.windows.count) windows  \(layout.updatedAt)")
        }
        guard let layout = store.layout(profile) else { return }
        if let fix = Displays.configurationFix(saved: layout.displays, current: displays) {
            print("== Display setup differs from saved: arrangement=\(fix.arrangementChanged) modes=\(fix.modes.keys.sorted())")
        } else {
            print("== Display setup matches the saved one")
        }
        var drift = 0, closed = 0
        let byKey = Dictionary(displays.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        for record in layout.windows.values {
            guard let live = capture.byID[record.windowID] else {
                if !capture.existing.contains(record.windowID) { closed += 1 }
                continue
            }
            guard let d = byKey[record.displayKey] else { continue }
            let target = record.relFrame.offsetBy(dx: d.bounds.minX, dy: d.bounds.minY)
            if !live.frame.isClose(to: target) {
                drift += 1
                print("  would move: \(record.appName) \(record.windowID)  \(live.frame) -> \(target)")
            }
        }
        print("== Dry run: \(drift) windows out of place, \(closed) closed (never reopened)")
    }
}
