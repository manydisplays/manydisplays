import AppKit
import ApplicationServices

/// Owns all state. Everything below runs on `queue`; the public entry points just hop onto it.
///
/// Lifecycle:
///   tracking  --(lock / sleep / displays reconfiguring)-->  frozen   (nothing is saved, the
///                                                                     last good layout is kept)
///   frozen    --(displays stable for a few seconds, unlocked)-->  restoring  -->  tracking
///   any       --(no external display)-->  inactive  (zero work: no observers, no timers)
final class Engine {
    static let shared = Engine()

    enum Mode: String {
        case starting, inactive, tracking, frozen, restoring, paused
    }

    struct ProfileSummary {
        let id: String
        let name: String
        let windowCount: Int
        let updatedAt: Date
        let isActive: Bool
    }

    struct Status {
        var mode: Mode = .starting
        var detail = ""
        var windowCount = 0
        var lastSave: Date?
        var lastRestore: String?
        var spaceMismatches = 0
        var pending = 0
        var profiles: [ProfileSummary] = []
    }

    let queue = DispatchQueue(label: "com.martinacuna.manydisplays.engine", qos: .utility)
    var onStatusChange: (() -> Void)?

    private let store = LayoutStore()
    private let apps = AppInfoCache()
    private let ownPID = getpid()

    private var mode: Mode = .starting
    private var detail = ""
    private var cycle = 0
    private var screenLocked = false
    private var asleep = false
    private var sawHotplug = false
    private var sawSleepOrLock = false
    private var arrangementFixedThisCycle = false
    private var firstEvaluation = true
    private var activeProfileID: String?
    /// Windows whose restore failed (e.g. the app refused); their saved position is protected
    /// from being overwritten until they are restored or the protection expires.
    private var pending: [CGWindowID: Date] = [:]
    private var titles: [CGWindowID: String] = [:]
    /// AX elements found during the current restore cycle, and windows a deep scan could not
    /// reach (apps that hide off-space windows); those wait until their desktop is visited.
    private var axElements: [CGWindowID: AXUIElement] = [:]
    private var unreachable: Set<CGWindowID> = []
    private var snapshotWork: DispatchWorkItem?
    private var settleWork: DispatchWorkItem?
    private var watchdogWork: DispatchWorkItem?
    private var flushWork: DispatchWorkItem?
    private var pendingRestoreWork: DispatchWorkItem?
    private var heartbeat: DispatchSourceTimer?
    private var lastSave: Date?
    private var lastRestore: String?
    private var spaceMismatches = 0

    private let statusLock = NSLock()
    private var _status = Status()

    var status: Status {
        statusLock.lock()
        defer { statusLock.unlock() }
        return _status
    }

    // MARK: - Entry points (any thread)

    func start() {
        queue.async {
            Log.info("ManyDisplays started (boot \(Boot.session), AX=\(AX.isTrusted))")
            self.publish()
            self.scheduleSettle(after: 1.0, reason: "launch")
        }
    }

    func displayReconfigBegan() {
        queue.async { self.freeze("displays reconfiguring") }
    }

    func displayReconfigEnded(hotplug: Bool) {
        queue.async {
            if hotplug { self.sawHotplug = true }
            if self.mode != .frozen { self.freeze("displays reconfigured") }
            self.scheduleSettle(after: 2.5, reason: "displays stable")
        }
    }

    func willSleep() {
        queue.async {
            self.checkpoint()
            self.asleep = true
            self.sawSleepOrLock = true
            self.freeze("Mac going to sleep")
        }
    }

    func didWake() {
        queue.async {
            self.asleep = false
            self.scheduleSettle(after: 3.0, reason: "Mac woke up")
        }
    }

    func screensDidSleep() {
        queue.async {
            self.checkpoint()
            self.sawSleepOrLock = true
            self.freeze("displays asleep")
        }
    }

    func screensDidWake() {
        queue.async { self.scheduleSettle(after: 3.0, reason: "displays awake") }
    }

    func screenLockChanged(locked: Bool) {
        queue.async {
            if locked {
                guard !self.screenLocked else { return }
                self.checkpoint()
                self.screenLocked = true
                self.sawSleepOrLock = true
                self.freeze("screen locked")
            } else {
                guard self.screenLocked else { return }
                self.screenLocked = false
                self.scheduleSettle(after: 1.5, reason: "unlocked")
            }
        }
    }

    func windowEvent() {
        queue.async { self.scheduleSnapshot(after: 1.5) }
    }

    func windowTitleMaybeChanged(_ element: AXUIElement) {
        queue.async {
            guard let id = AX.windowID(element), let title = AX.title(element) else { return }
            if self.titles.count > 3000 { self.titles.removeAll() }
            self.titles[id] = title
        }
    }

    func activeSpaceChanged() {
        queue.async {
            self.scheduleSnapshot(after: 1.0)
            guard self.mode == .tracking, !self.pending.isEmpty else { return }
            self.pendingRestoreWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.restorePending() }
            self.pendingRestoreWork = work
            self.queue.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
    }

    func accessibilityGranted() {
        queue.async {
            Log.info("Accessibility permission granted")
            if self.mode == .tracking { DispatchQueue.main.async { AXHub.shared.start() } }
            self.publish()
        }
    }

    /// Manual save: the current window positions become the truth.
    func saveNow() {
        queue.async {
            guard !Settings.paused else { return }
            let displays = Displays.current()
            guard Displays.hasExternal(displays) else {
                Log.info("Manual save ignored: no external displays")
                return
            }
            self.pending.removeAll()
            self.activeProfileID = Displays.profileID(displays)
            if self.mode != .tracking { self.beginTracking() }
            self.snapshot()
            self.store.flush()
            Log.info("Manual save")
        }
    }

    func restoreNow() {
        queue.async {
            guard !Settings.paused else { return }
            let displays = Displays.current()
            guard Displays.hasExternal(displays) else { return }
            let profile = Displays.profileID(displays)
            guard let layout = self.store.layout(profile) else {
                Log.info("Manual restore: nothing saved for this display setup")
                return
            }
            self.activeProfileID = profile
            self.startRestore(layout: layout, displays: displays, reason: "manual", allowArrangement: true)
        }
    }

    func setPaused(_ paused: Bool) {
        queue.async {
            Settings.paused = paused
            Log.info(paused ? "Tracking paused" : "Tracking resumed")
            if paused {
                self.cycle += 1
                self.stopTracking()
                self.setMode(.paused, "paused by user")
            } else {
                self.setMode(.frozen, "resuming")
                self.scheduleSettle(after: 0.2, reason: "resume")
            }
        }
    }

    func forgetProfile(_ id: String) {
        queue.async {
            self.store.remove(id)
            self.store.flush()
            Log.info("Forgot setup: \(id)")
            self.publish()
        }
    }

    func flushSync() {
        queue.sync {
            if self.mode == .tracking { self.snapshot() }
            self.store.flush()
        }
    }

    // MARK: - State machine

    private func setMode(_ newMode: Mode, _ newDetail: String = "") {
        mode = newMode
        detail = newDetail
        publish()
    }

    private func freeze(_ reason: String) {
        guard mode != .paused else { return }
        cycle += 1
        snapshotWork?.cancel()
        snapshotWork = nil
        pendingRestoreWork?.cancel()
        settleWork?.cancel()
        if mode != .frozen { Log.info("On hold: \(reason)") }
        setMode(.frozen, reason)
        DispatchQueue.main.async { RestoreOverlay.shared.hide() }

        // Safety net in case a wake/unlock notification never arrives.
        watchdogWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.mode == .frozen else { return }
            self.settled(reason: "watchdog")
        }
        watchdogWork = work
        queue.asyncAfter(deadline: .now() + 30, execute: work)
    }

    /// Takes a final snapshot right before the system starts moving things around.
    private func checkpoint() {
        guard mode == .tracking else { return }
        snapshot()
        store.flush()
    }

    private func scheduleSettle(after delay: TimeInterval, reason: String) {
        guard mode != .paused || reason == "resume" else { return }
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.settled(reason: reason) }
        settleWork = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func settled(reason: String) {
        if screenLocked || asleep {
            setMode(.frozen, screenLocked ? "waiting for unlock" : "waiting for wake")
            return
        }
        evaluate(reason: reason)
    }

    private func evaluate(reason: String) {
        if Settings.paused {
            stopTracking()
            setMode(.paused, "paused by user")
            return
        }
        let displays = Displays.current()
        guard Displays.hasExternal(displays) else {
            if mode != .inactive { Log.info("No external displays: idle") }
            activeProfileID = nil
            pending.removeAll()
            resetCycleFlags()
            stopTracking()
            setMode(.inactive, "no external displays")
            return
        }

        let profile = Displays.profileID(displays)
        let isFirst = firstEvaluation
        firstEvaluation = false
        if profile != activeProfileID {
            Log.info("Display setup: \(Displays.profileName(displays.map(DisplayInfo.init)))")
            pending.removeAll()
        }
        activeProfileID = profile

        guard let layout = store.layout(profile) ?? (isFirst ? nil : closestLayout(to: displays)) else {
            Log.info("New display setup, tracking started")
            beginTracking()
            return
        }
        if layout.profileID != profile {
            Log.info("New display setup; restoring from the closest one: \(Displays.profileName(layout.displays))")
        }

        if isFirst {
            // App (re)started: windows still have their ids unless apps or the Mac restarted.
            // Re-link windows that changed id and only restore those.
            let rebound = rebindDeadRecords(profile: profile)
            if rebound.isEmpty {
                beginTracking()
            } else {
                Log.info("Re-linked \(rebound.count) windows after restart")
                startRestore(layout: store.layout(profile) ?? layout, displays: displays, reason: "launch",
                             only: rebound, allowArrangement: false)
            }
            return
        }

        startRestore(layout: layout, displays: displays, reason: reason, allowArrangement: true)
    }

    /// For a combination never seen before (e.g. the same monitors but with the lid open),
    /// borrow the layout that shares the most external monitors; windows go back to the
    /// monitors that are present, the rest stay where macOS put them.
    private func closestLayout(to displays: [LiveDisplay]) -> Layout? {
        let external = Set(displays.filter { !$0.isBuiltin }.map(\.key))
        return store.layouts.values
            .map { layout -> (Layout, Int) in
                (layout, Set(layout.displays.filter { !$0.isBuiltin }.map(\.key)).intersection(external).count)
            }
            .filter { $0.1 > 0 }
            .max { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.updatedAt < $1.0.updatedAt }?
            .0
    }

    private func resetCycleFlags() {
        sawHotplug = false
        sawSleepOrLock = false
        arrangementFixedThisCycle = false
    }

    private func beginTracking() {
        cycle += 1
        watchdogWork?.cancel()
        resetCycleFlags()
        setMode(.tracking)
        DispatchQueue.main.async { AXHub.shared.start() }
        startHeartbeat()
        scheduleSnapshot(after: 0.5)
    }

    private func stopTracking() {
        snapshotWork?.cancel()
        snapshotWork = nil
        heartbeat?.cancel()
        heartbeat = nil
        DispatchQueue.main.async { AXHub.shared.stop() }
        store.flush()
    }

    private func startHeartbeat() {
        guard heartbeat == nil else { return }
        // Catches changes that produce no AX notification (e.g. moving a window between
        // desktops in Mission Control). Generous leeway lets the system coalesce wakeups.
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 20, repeating: 20, leeway: .seconds(5))
        timer.setEventHandler { [weak self] in self?.scheduleSnapshot(after: 0) }
        timer.resume()
        heartbeat = timer
    }

    // MARK: - Saving

    private func scheduleSnapshot(after delay: TimeInterval) {
        guard mode == .tracking, snapshotWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.snapshotWork = nil
            self?.snapshot()
        }
        snapshotWork = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func snapshot() {
        guard mode == .tracking, let profile = activeProfileID else { return }
        let displays = Displays.current()
        guard Displays.profileID(displays) == profile else {
            // Displays changed under us without a callback yet: do not save a shuffled layout.
            freeze("display change detected")
            scheduleSettle(after: 2.5, reason: "displays stable")
            return
        }

        let topology = Spaces.topology()
        let capture = WindowList.capture(topology: topology, ownPID: ownPID)
        let now = Date()
        pending = pending.filter { $0.value > now && capture.existing.contains($0.key) }

        var layout = store.layout(profile) ?? Layout(profileID: profile)
        layout.displays = displays.map(DisplayInfo.init)
        layout.bootSession = Boot.session
        // Windows that no longer exist were closed: forget them so they are never "restored".
        var windows = layout.windows.filter { capture.existing.contains(CGWindowID($0.key) ?? 0) }

        for window in capture.trackable {
            if pending[window.id] != nil { continue }
            guard let display = Displays.best(for: window.frame, in: displays) else { continue }
            let key = String(window.id)
            let app = apps.info(window.pid)
            let spaceID = window.spaces.count == 1 ? window.spaces[0] : nil
            windows[key] = WindowRecord(
                windowID: window.id,
                pid: window.pid,
                bundleID: app.bundleID,
                appName: app.name ?? window.ownerName,
                title: window.title ?? titles[window.id] ?? windows[key]?.title,
                displayKey: display.key,
                relFrame: window.frame.offsetBy(dx: -display.bounds.minX, dy: -display.bounds.minY),
                spaceID: spaceID,
                spaceIndex: spaceID.flatMap(topology.index(of:)),
                onAllSpaces: window.spaces.count > 1,
                fullscreen: window.spaces.contains { topology.types[$0] == 4 }
            )
        }
        layout.windows = windows

        if store.put(layout) { scheduleFlush() }
        lastSave = now
        publish()
    }

    private func scheduleFlush() {
        flushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.store.flush() }
        flushWork = work
        queue.asyncAfter(deadline: .now() + 3, execute: work)
    }

    // MARK: - Restoring

    private struct PassResult {
        var moved = 0
        var failed: Set<CGWindowID> = []
        var spaceMismatches = 0
        var considered = 0
    }

    private func startRestore(layout: Layout, displays: [LiveDisplay], reason: String,
                              only: Set<CGWindowID>? = nil, allowArrangement: Bool) {
        cycle += 1
        let myCycle = cycle
        watchdogWork?.cancel()
        axElements.removeAll()
        unreachable.removeAll()
        setMode(.restoring, reason)

        if allowArrangement, Settings.fixArrangement, !arrangementFixedThisCycle,
           sawHotplug || sawSleepOrLock || reason == "manual",
           let origins = Displays.arrangementFix(saved: layout.displays, current: displays) {
            arrangementFixedThisCycle = true
            Log.info("macOS changed the display arrangement; restoring the saved one")
            if Displays.applyArrangement(origins, current: displays) {
                // The reconfiguration callbacks will freeze and settle again, then restore windows.
                setMode(.frozen, "fixing display arrangement")
                scheduleSettle(after: 3.0, reason: reason)
                return
            }
            Log.info("Could not change the display arrangement")
        }

        guard AX.isTrusted else {
            Log.info("No Accessibility permission: cannot move windows")
            lastRestore = "Accessibility permission missing"
            beginTracking()
            return
        }

        // macOS keeps nudging windows for a few seconds after displays come back,
        // so run a few cheap passes; each one only touches windows that drifted.
        let delays: [TimeInterval] = [0, 1.5, 4.0]
        func runPass(_ index: Int, moved: Int) {
            guard cycle == myCycle else { return }
            let current = store.layout(layout.profileID) ?? layout
            var result = restorePass(layout: current, only: only, deep: true, overlay: index == 0)
            result.moved += moved
            if index + 1 < delays.count {
                queue.asyncAfter(deadline: .now() + (delays[index + 1] - delays[index])) {
                    runPass(index + 1, moved: result.moved)
                }
                return
            }
            finishRestore(result, reason: reason)
        }
        runPass(0, moved: 0)
    }

    private func finishRestore(_ result: PassResult, reason: String) {
        let expiry = Date().addingTimeInterval(30 * 60)
        for id in result.failed { pending[id] = expiry }
        spaceMismatches = result.spaceMismatches
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        var summary = "\(formatter.string(from: Date())): \(result.moved) moved of \(result.considered)"
        if !result.failed.isEmpty { summary += ", \(result.failed.count) pending" }
        lastRestore = summary
        DispatchQueue.main.async { RestoreOverlay.shared.hide() }
        Log.info("Restore (\(reason)) \(summary); on another Space: \(result.spaceMismatches)")
        beginTracking()
    }

    /// Re-tries windows that could not be restored, e.g. after the user switches to their desktop.
    private func restorePending() {
        guard mode == .tracking, !pending.isEmpty, let profile = activeProfileID,
              let layout = store.layout(profile) else { return }
        let ids = Set(pending.keys)
        let result = restorePass(layout: layout, only: ids, deep: false, overlay: false)
        for id in ids where !result.failed.contains(id) { pending.removeValue(forKey: id) }
        if result.moved > 0 { Log.info("Restored \(result.moved) pending windows") }
        publish()
    }

    private func restorePass(layout: Layout, only: Set<CGWindowID>?, deep: Bool, overlay: Bool) -> PassResult {
        var result = PassResult()
        let displays = Displays.current()
        let byKey = Dictionary(displays.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let savedDisplays = Dictionary(layout.displays.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let topology = Spaces.topology()
        let capture = WindowList.capture(topology: topology, ownPID: ownPID)

        var jobs: [pid_t: [(CGWindowID, CGRect)]] = [:]
        for record in layout.windows.values {
            if let only, !only.contains(record.windowID) { continue }
            // Closed windows are never reopened; minimized/hidden ones are left alone.
            guard let live = capture.byID[record.windowID], !record.fullscreen,
                  !live.spaces.contains(where: { topology.types[$0] == 4 }),
                  let display = byKey[record.displayKey] else { continue }
            result.considered += 1

            if !record.onAllSpaces,
               let wanted = record.spaceID.flatMap({ topology.types[$0] != nil ? $0 : nil })
                ?? topology.space(at: record.spaceIndex),
               !live.spaces.contains(wanted) {
                result.spaceMismatches += 1
            }

            let target = targetFrame(record, saved: savedDisplays[record.displayKey], current: display)
            if live.frame.isClose(to: target) { continue }
            jobs[live.pid, default: []].append((record.windowID, target))
        }

        // Only veil the screens when there is actually something to put back.
        if overlay, !jobs.isEmpty, Settings.blurWhileRestoring {
            DispatchQueue.main.async { RestoreOverlay.shared.show() }
        }

        // Phase 1 moves everything reachable cheaply (current desktop + cached elements);
        // phase 2 deep-scans only for what is left, so slow apps never delay the rest.
        var remaining = jobs
        for phaseDeep in deep ? [false, true] : [false] {
            var next: [pid_t: [(CGWindowID, CGRect)]] = [:]
            for (pid, list) in remaining {
                let app = AX.application(pid)
                let wanted = Set(list.map(\.0))
                var elements = axElements.filter { wanted.contains($0.key) }
                let missing = wanted.subtracting(elements.keys).subtracting(phaseDeep ? unreachable : [])
                if !missing.isEmpty {
                    let found = AX.elements(pid: pid, wanted: missing, deep: phaseDeep)
                    elements.merge(found) { a, _ in a }
                    axElements.merge(found) { a, _ in a }
                    if phaseDeep { unreachable.formUnion(missing.subtracting(found.keys)) }
                }
                for (id, target) in list {
                    guard let element = elements[id] else {
                        if !phaseDeep && deep {
                            next[pid, default: []].append((id, target))
                            continue
                        }
                        // Visible but not an AX window (e.g. Chrome helper strips): nothing to do.
                        // Off-space and hidden from AX: retry when its desktop becomes active.
                        let onActive = capture.byID[id].map { !Set($0.spaces).isDisjoint(with: topology.active) } ?? true
                        if !onActive { result.failed.insert(id) }
                        continue
                    }
                    if AX.isMinimized(element) { continue }
                    if AX.setFrame(element, app: app, to: target) {
                        result.moved += 1
                    } else {
                        axElements.removeValue(forKey: id)
                        result.failed.insert(id)
                    }
                }
            }
            remaining = next
        }
        return result
    }

    private func targetFrame(_ record: WindowRecord, saved: DisplayInfo?, current: LiveDisplay) -> CGRect {
        var rel = record.relFrame
        let bounds = current.bounds
        if let saved, saved.frame.size != bounds.size, saved.frame.width > 0, saved.frame.height > 0 {
            // Resolution changed: keep proportions and stay inside the display.
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

    /// After a reboot or an app relaunch the window ids change. Match the saved records to the
    /// new windows of the same app by title (or when the app has exactly one window).
    private func rebindDeadRecords(profile: String) -> Set<CGWindowID> {
        guard var layout = store.layout(profile) else { return [] }
        let capture = WindowList.capture(topology: Spaces.topology(), ownPID: ownPID)
        let dead = layout.windows.values.filter { !capture.existing.contains($0.windowID) }
        guard !dead.isEmpty else { return [] }

        let known = Set(layout.windows.values.map(\.windowID))
        var candidates: [String: [LiveWindow]] = [:]
        for window in capture.trackable where !known.contains(window.id) {
            if let bundle = apps.info(window.pid).bundleID { candidates[bundle, default: []].append(window) }
        }
        guard !candidates.isEmpty else {
            layout.windows = layout.windows.filter { capture.existing.contains($0.value.windowID) }
            store.put(layout)
            return []
        }

        // Titles of the new windows (CGWindowList only has them with Screen Recording permission).
        var liveTitles: [CGWindowID: String] = [:]
        if AX.isTrusted {
            for (_, windows) in candidates {
                guard let pid = windows.first?.pid else { continue }
                for (id, element) in AX.elements(pid: pid, wanted: Set(windows.map(\.id)), deep: true) {
                    if let title = AX.title(element) { liveTitles[id] = title }
                }
            }
        }

        let deadPerBundle = Dictionary(grouping: dead, by: { $0.bundleID ?? "" }).mapValues(\.count)
        var rebound: Set<CGWindowID> = []
        for record in dead.sorted(by: { ($0.title ?? "") > ($1.title ?? "") }) {
            guard let bundle = record.bundleID, var list = candidates[bundle], !list.isEmpty else { continue }
            var index: Int?
            if let title = record.title {
                index = list.firstIndex { ($0.title ?? liveTitles[$0.id]) == title }
            }
            if index == nil, list.count == 1, deadPerBundle[bundle] == 1 { index = 0 }
            guard let i = index else { continue }
            let window = list.remove(at: i)
            candidates[bundle] = list
            var updated = record
            updated.windowID = window.id
            updated.pid = window.pid
            layout.windows.removeValue(forKey: String(record.windowID))
            layout.windows[String(window.id)] = updated
            rebound.insert(window.id)
        }
        layout.windows = layout.windows.filter { capture.existing.contains($0.value.windowID) }
        store.put(layout)
        store.flush()
        return rebound
    }

    // MARK: - Status

    private func publish() {
        var status = Status()
        status.mode = mode
        status.detail = detail
        status.lastSave = lastSave
        status.lastRestore = lastRestore
        status.spaceMismatches = spaceMismatches
        status.pending = pending.count
        if let id = activeProfileID { status.windowCount = store.layout(id)?.windows.count ?? 0 }
        status.profiles = store.layouts.values
            .map {
                ProfileSummary(id: $0.profileID, name: Displays.profileName($0.displays),
                               windowCount: $0.windows.count, updatedAt: $0.updatedAt,
                               isActive: $0.profileID == activeProfileID)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
        statusLock.lock()
        _status = status
        statusLock.unlock()
        DispatchQueue.main.async { [weak self] in self?.onStatusChange?() }
    }
}
