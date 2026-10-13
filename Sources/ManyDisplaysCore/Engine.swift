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

    let queue = DispatchQueue(label: AppIdentity.bundleID + ".engine", qos: .utility)
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
    /// Display fixes already attempted in this wake/reconnect cycle (each runs at most once).
    private var displayFixesDone: Set<String> = []
    /// HDR state is read through MonitorPanel (~25 ms), so it is cached until displays change.
    private var hdrCache: [CGDirectDisplayID: Bool] = [:]
    private var hdrCacheStale = true
    private var firstEvaluation = true
    /// Launched behind the lock screen (e.g. updated while away): restore normally on unlock.
    private var startedLocked = false
    /// `--restore-on-launch`: put windows back right away instead of just starting to track.
    var restoreOnLaunch = CommandLine.arguments.contains("--restore-on-launch")
    private var activeProfileID: String?
    /// Windows whose restore failed (e.g. the app refused); their saved position is protected
    /// from being overwritten until they are restored or the protection expires.
    private var pending: [CGWindowID: Date] = [:]
    /// How many times a pending window was retried on its desktop without sticking.
    private var pendingAttempts: [CGWindowID: Int] = [:]
    /// Right after a restore, apps (VS Code, Electron…) or macOS sometimes move windows back.
    /// Until this date, such drift is undone instead of being saved as the new position.
    private var guardUntil = Date.distantPast
    private var guardAttempts: [CGWindowID: Int] = [:]
    private var guardStart = Date.distantPast
    /// Windows restored while their desktop was not visible. macOS/apps often re-adjust them when
    /// that desktop is first shown, so they stay guarded until then (plus a few seconds).
    private struct Watch {
        let since: Date
        var visibleSince: Date?
    }

    private var offSpaceWatch: [CGWindowID: Watch] = [:]
    /// Windows the user moved/resized themselves (mouse or shortcut right before the change).
    private var userMovedAt: [CGWindowID: Date] = [:]
    /// Window-server windows that are not real AX windows (e.g. Chrome's 89 px helper strips).
    private var nonAXWindows: Set<CGWindowID> = []
    private var lastRestoreAt = Date.distantPast
    private var overlayShownAt: Date?
    private var restoreStartedAt = Date()
    private var lastReconfigAt = Date.distantPast
    /// Windows a deep scan could not reach in an earlier restore (apps that hide off-desktop
    /// windows). Not scanned again; they are placed when their desktop is shown.
    private var knownUnreachable: Set<CGWindowID> = []
    private var titles: [CGWindowID: String] = [:]
    /// AX elements found during the current restore cycle.
    private var axElements: [CGWindowID: AXUIElement] = [:]
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
            Log
                .info(
                    "\(AppIdentity.name) \(AppIdentity.version) started (boot \(Boot.session), AX=\(AX.isTrusted), macOS \(ProcessInfo.processInfo.operatingSystemVersionString))"
                )
            if !PrivateAPI.isAvailable {
                Log
                    .info(
                        "This macOS lacks private symbols the app needs (\(PrivateAPI.missing.joined(separator: ", "))); windows cannot be tracked"
                    )
            }
            if let session = CGSessionCopyCurrentDictionary() as? [String: Any],
               (session["CGSSessionScreenIsLocked"] as? Bool) == true {
                Log.info("Started while the screen is locked; will restore on unlock")
                self.screenLocked = true
                self.sawSleepOrLock = true
                self.startedLocked = true
            }
            self.publish()
            self.scheduleSettle(after: 1.0, reason: "launch")
        }
    }

    func displayReconfigBegan() {
        queue.async {
            self.lastReconfigAt = Date()
            self.freeze("displays reconfiguring")
        }
    }

    func displayReconfigEnded(hotplug: Bool) {
        queue.async {
            Log.info("Display reconfigured\(hotplug ? " (connected/disconnected)" : "")")
            self.lastReconfigAt = Date()
            if hotplug {
                self.sawHotplug = true
            }
            self.hdrCacheStale = true
            if self.mode != .frozen {
                self.freeze("displays reconfigured")
            }
            self.scheduleSettle(after: Tuning.displaySettle, reason: "displays stable")
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
            self.scheduleSettle(after: Tuning.wakeSettle, reason: "Mac woke up")
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
        queue.async { self.scheduleSettle(after: Tuning.wakeSettle, reason: "displays awake") }
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
                // Displays usually reconnect before the password is typed; if they have been
                // stable for a while there is no need to wait long.
                let calm = Date().timeIntervalSince(self.lastReconfigAt) > Tuning.displaySettle
                let delay: TimeInterval = calm ? 0.3 : 1.5
                // Veil the screens right away if windows are visibly out of place.
                if Settings.blurWhileRestoring, !Settings.paused, self.overlayShownAt == nil, self.visibleWindowsLookMoved() {
                    self.overlayShownAt = Date()
                    let estimate = Settings.overlayDuration + delay
                    DispatchQueue.main.async { RestoreOverlay.shared.show(estimate: estimate) }
                }
                self.scheduleSettle(after: delay, reason: "unlocked")
            }
        }
    }

    func windowMoved(_ element: AXUIElement, byUser: Bool) {
        queue.async {
            if byUser, let id = AX.windowID(element) {
                if self.userMovedAt.count > Tuning.userMoveCacheLimit {
                    self.userMovedAt.removeAll()
                }
                self.userMovedAt[id] = Date()
            }
            self.scheduleSnapshot(after: Tuning.snapshotDebounce)
        }
    }

    func windowEvent() {
        queue.async { self.scheduleSnapshot(after: Tuning.snapshotDebounce) }
    }

    func windowTitleMaybeChanged(_ element: AXUIElement) {
        queue.async {
            guard let id = AX.windowID(element), let title = AX.title(element) else { return }
            if self.titles.count > Tuning.titleCacheLimit {
                self.titles.removeAll()
            }
            self.titles[id] = title
        }
    }

    func activeSpaceChanged() {
        queue.async {
            self.scheduleSnapshot(after: Tuning.spaceChangeDebounce)
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
            if self.mode == .tracking {
                DispatchQueue.main.async { AXHub.shared.start() }
            }
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
            if self.mode != .tracking {
                self.beginTracking()
            }
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
            if self.mode == .tracking {
                self.snapshot()
            }
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
        if mode != .frozen {
            Log.info("On hold: \(reason)")
        }
        setMode(.frozen, reason)
        overlayShownAt = nil
        DispatchQueue.main.async { RestoreOverlay.shared.hide() }

        // Safety net in case a wake/unlock notification never arrives.
        watchdogWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.mode == .frozen else { return }
            self.settled(reason: "watchdog")
        }
        watchdogWork = work
        queue.asyncAfter(deadline: .now() + Tuning.watchdog, execute: work)
    }

    /// Takes a final snapshot right before the system starts moving things around.
    /// Called on lock/sleep. Deliberately does NOT take a snapshot: at that instant macOS is
    /// already animating (the lock screen shrinks windows), so a snapshot would record fake
    /// frames. Snapshots run continuously, so the last one is recent and correct.
    private func checkpoint() {
        snapshotWork?.cancel()
        snapshotWork = nil
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
            if fixBuiltinDisplayAfterUndock(displays) {
                return
            }
            dropOverlay()
            if mode != .inactive {
                Log.info("No external displays: idle")
            }
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
            Log.info("Display setup: \(Displays.profileName(displays.map { DisplayInfo($0) }))")
            pending.removeAll()
            pendingAttempts.removeAll()
            offSpaceWatch.removeAll()
        }
        activeProfileID = profile

        // Only after a (re)connection: mirroring the user turned on before locking the screen
        // for a presentation must survive the unlock.
        if Settings.fixArrangement, sawHotplug, !displayFixesDone.contains("mirror") {
            displayFixesDone.insert("mirror")
            let mirrored = Displays.all().filter { $0.mirrorOf != kCGNullDirectDisplay }
            let extended = Set(displays.map(\.key)).union(mirrored.map(\.key))
            if !mirrored.isEmpty, store.layouts.values.contains(where: { Set($0.displays.map(\.key)) == extended }) {
                Log.info("macOS turned on mirroring for \(mirrored.count) display(s) that were extended; turning it off")
                if Displays.unmirror(mirrored.map(\.id)) {
                    setMode(.frozen, "turning off mirroring")
                    scheduleSettle(after: Tuning.displayFixSettle, reason: reason)
                    return
                }
            }
        }

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
            if !rebound.isEmpty {
                Log.info("Re-linked \(rebound.count) windows after restart")
            }
            if !startedLocked && !restoreOnLaunch {
                if rebound.isEmpty {
                    beginTracking()
                } else {
                    startRestore(
                        layout: store.layout(profile) ?? layout,
                        displays: displays,
                        reason: "launch",
                        only: rebound,
                        allowArrangement: false
                    )
                }
                return
            }
            startedLocked = false
            restoreOnLaunch = false
            startRestore(
                layout: store.layout(profile) ?? layout,
                displays: displays,
                reason: reason,
                allowArrangement: true
            )
            return
        }

        startRestore(layout: layout, displays: displays, reason: reason, allowArrangement: true)
    }

    /// For a combination never seen before (e.g. the same monitors but with the lid open),
    /// borrow the layout that shares the most external monitors; windows go back to the
    /// monitors that are present, the rest stay where macOS put them.
    private func closestLayout(to displays: [LiveDisplay]) -> Layout? {
        LayoutMath.closestLayout(to: displays, among: Array(store.layouts.values))
    }

    /// Puts the display setup back the way it was saved, one step per settle: rotation, then
    /// resolution/refresh rate/arrangement, then HDR. Returns true if a change was applied.
    private func applyNextDisplayFix(layout: Layout, displays: [LiveDisplay], reason: String) -> Bool {
        func applied(_ what: String) -> Bool {
            setMode(.frozen, what)
            scheduleSettle(after: Tuning.displayFixSettle, reason: reason)
            return true
        }

        if displayFixesDone.insert("rotation").inserted {
            let fix = Displays.rotationFix(saved: layout.displays, current: displays)
            if !fix.isEmpty {
                Log.info("macOS reset the rotation of \(fix.count) display(s); restoring it")
                DispatchQueue.main.async {
                    for (id, degrees) in fix where !DisplayPanel.setRotation(degrees, for: id) {
                        Log.info("Could not rotate display \(id)")
                    }
                }
                return applied("restoring display rotation")
            }
        }

        if displayFixesDone.insert("config").inserted,
           let fix = Displays.configurationFix(saved: layout.displays, current: displays) {
            var what: [String] = []
            if fix.arrangementChanged {
                what.append("arrangement")
            }
            if !fix.modes.isEmpty {
                what.append("resolution/refresh rate of \(fix.modes.count) display(s)")
            }
            Log.info("macOS changed the display \(what.joined(separator: " and ")); restoring the saved setup")
            if Displays.apply(fix, current: displays) {
                return applied("restoring display setup")
            }
            Log.info("Could not change the display configuration")
        }

        if displayFixesDone.insert("hdr").inserted {
            let fix = Displays.hdrFix(saved: layout.displays, current: displays)
            if !fix.isEmpty {
                Log.info("macOS changed HDR on \(fix.count) display(s); restoring it")
                DispatchQueue.main.async {
                    for (id, on) in fix where !DisplayPanel.setHDR(on, for: id) {
                        Log.info("Could not change HDR on display \(id)")
                    }
                }
                return applied("restoring HDR")
            }
        }
        return false
    }

    /// Some Macs come back from a dock with the built-in panel at the wrong resolution
    /// (huge menu bar). Remember the built-in mode while undocked and put it back after
    /// unplugging. Only reacts right after a disconnect; never touches windows.
    private func fixBuiltinDisplayAfterUndock(_ displays: [LiveDisplay]) -> Bool {
        guard Settings.fixArrangement, displays.count == 1, let builtin = displays.first, builtin.isBuiltin else {
            return false
        }
        let profile = Displays.profileID(displays)
        if !sawHotplug {
            // Calm state (wake, unlock, or a deliberate change): this is the mode to keep.
            var layout = store.layout(profile) ?? Layout(profileID: profile)
            layout.displays = displays.map { DisplayInfo($0) }
            layout.windows = [:]
            if store.put(layout) {
                scheduleFlush()
            }
            return false
        }
        guard displayFixesDone.insert("builtin").inserted, let saved = store.layout(profile),
              let fix = Displays.configurationFix(saved: saved.displays, current: displays), !fix.modes.isEmpty
        else { return false }
        Log.info("Built-in display came back at a different resolution after undocking; restoring it")
        guard Displays.apply(fix, current: displays) else { return false }
        setMode(.frozen, "restoring built-in display")
        scheduleSettle(after: Tuning.displaySettle, reason: "displays stable")
        return true
    }

    private func resetCycleFlags() {
        sawHotplug = false
        sawSleepOrLock = false
        displayFixesDone.removeAll()
    }

    private func dropOverlay() {
        guard overlayShownAt != nil else { return }
        overlayShownAt = nil
        DispatchQueue.main.async { RestoreOverlay.shared.hide() }
    }

    private func beginTracking() {
        dropOverlay()
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
        timer.schedule(deadline: .now() + Tuning.heartbeatInterval, repeating: Tuning.heartbeatInterval, leeway: .seconds(5))
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
            scheduleSettle(after: Tuning.displaySettle, reason: "displays stable")
            return
        }

        let topology = Spaces.topology()
        let capture = WindowList.capture(topology: topology, ownPID: ownPID, apps: apps)
        let now = Date()
        pending = pending.filter { $0.value > now && capture.existing.contains($0.key) }

        var layout = store.layout(profile) ?? Layout(profileID: profile)
        let drifted = guardedDrift(layout: layout, capture: capture, displays: displays, topology: topology)
        let byKey = Dictionary(displays.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let savedDisplays = Dictionary(layout.displays.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        if hdrCacheStale {
            hdrCache = DisplayPanel.hdrStates()
            hdrCacheStale = false
        }
        layout.displays = displays.map { DisplayInfo($0, hdr: hdrCache[$0.id]) }
        layout.bootSession = Boot.session
        // Windows that no longer exist were closed: forget them so they are never "restored".
        var windows = layout.windows.filter { capture.existing.contains(CGWindowID($0.key) ?? 0) }

        for window in capture.trackable {
            if pending[window.id] != nil || drifted.contains(window.id) {
                continue
            }
            let key = String(window.id)
            let onActiveDesktop = !Set(window.spaces).isDisjoint(with: topology.active)
            var frame = window.frame
            if let old = layout.windows[key], let oldDisplay = byKey[old.displayKey] {
                let oldFrame = LayoutMath.targetFrame(old, saved: savedDisplays[old.displayKey], current: oldDisplay)
                if !frame.isClose(to: oldFrame) {
                    // Windows on desktops you are not looking at cannot have been moved by you;
                    // what the window server reports for them is an animation in progress.
                    guard onActiveDesktop else { continue }
                    if let real = axFrame(of: window) {
                        guard real.matches(frame) else { continue } // Mission Control / swipe in progress
                        frame = real
                    } else if (userMovedAt[window.id] ?? .distantPast) < now.addingTimeInterval(-Tuning.userMoveMemory),
                              !UserInput.happened(within: Tuning.userInputWindow) {
                        continue // cannot confirm with the app and nobody touched anything: ignore
                    }
                }
            } else if onActiveDesktop, let real = axFrame(of: window) {
                frame = real
            }
            guard let display = Displays.best(for: frame, in: displays) else { continue }
            let app = apps.info(window.pid)
            let spaceID = window.spaces.count == 1 ? window.spaces[0] : nil
            windows[key] = WindowRecord(
                windowID: window.id,
                pid: window.pid,
                bundleID: app.bundleID,
                appName: app.name ?? window.ownerName,
                title: window.title ?? titles[window.id] ?? windows[key]?.title,
                displayKey: display.key,
                relFrame: frame.offsetBy(dx: -display.bounds.minX, dy: -display.bounds.minY),
                spaceID: spaceID,
                spaceIndex: spaceID.flatMap(topology.index(of:)),
                onAllSpaces: window.spaces.count > 1,
                fullscreen: window.spaces.contains { topology.types[$0] == 4 }
            )
        }
        if now.timeIntervalSince(lastRestoreAt) < Tuning.postRestoreDiagnostics {
            // Diagnostics: who moves windows after a restore, and when.
            var changes: [String] = []
            for (key, new) in windows {
                guard let old = layout.windows[key],
                      !old.relFrame.isClose(to: new.relFrame) || old.displayKey != new.displayKey else { continue }
                let id = new.windowID
                let who = (userMovedAt[id] ?? .distantPast) > now.addingTimeInterval(-Tuning.userMoveMemory) ? "user" : "not user"
                changes.append("\(new.appName) \(id) \(rect(old.relFrame)) -> \(rect(new.relFrame)) [\(who)]")
            }
            if !changes.isEmpty {
                Log
                    .info("Saved window changes \(Int(now.timeIntervalSince(lastRestoreAt)))s after restore: " + changes.prefix(8)
                        .joined(separator: "; "))
            }
        }
        layout.windows = windows

        if store.put(layout) {
            scheduleFlush()
        }
        if !drifted.isEmpty {
            let result = restorePass(layout: layout, only: drifted, deep: false, overlay: false)
            if result.moved == 0 {
                for id in drifted {
                    guardAttempts[id] = Tuning.guardMaxAttempts
                }
            }
        }
        lastSave = now
        publish()
    }

    /// During the guard period after a restore, windows that left their restored position
    /// without the user dragging them are put back (up to 3 times each) instead of saved.
    private func guardedDrift(
        layout: Layout,
        capture: WindowCapture,
        displays: [LiveDisplay],
        topology: SpaceTopology
    ) -> Set<CGWindowID> {
        let now = Date()
        offSpaceWatch = offSpaceWatch.filter { entry in
            guard now.timeIntervalSince(entry.value.since) < Tuning.offSpaceWatchMax,
                  capture.existing.contains(entry.key) else { return false }
            if let visible = entry.value.visibleSince {
                return now.timeIntervalSince(visible) < Tuning.offSpaceWatchAfterVisible
            }
            return true
        }
        let globalGuard = now < guardUntil
        guard globalGuard || !offSpaceWatch.isEmpty else { return [] }
        if NSEvent.pressedMouseButtons != 0 || UserInput.happened(within: 1.0) {
            return [] // the user is busy moving things right now; check again on the next snapshot
        }
        let byKey = Dictionary(displays.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let savedDisplays = Dictionary(layout.displays.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var drifted: Set<CGWindowID> = []
        var details: [String] = []
        for window in capture.trackable where pending[window.id] == nil && !nonAXWindows.contains(window.id) {
            if var watch = offSpaceWatch[window.id], watch.visibleSince == nil,
               !Set(window.spaces).isDisjoint(with: topology.active) {
                watch.visibleSince = now
                offSpaceWatch[window.id] = watch
            }
            let watchedSince = offSpaceWatch[window.id]?.since
            guard globalGuard || watchedSince != nil else { continue }
            let guardFrom = min(watchedSince ?? guardStart, guardStart)
            guard guardAttempts[window.id, default: 0] < Tuning.guardMaxAttempts,
                  (userMovedAt[window.id] ?? .distantPast) < guardFrom,
                  let record = layout.windows[String(window.id)], !record.fullscreen,
                  let display = byKey[record.displayKey] else { continue }
            // Only judge what is on screen, and confirm with the app (animations look like drift).
            guard !Set(window.spaces).isDisjoint(with: topology.active) else { continue }
            let target = LayoutMath.targetFrame(record, saved: savedDisplays[record.displayKey], current: display)
            if !isAt(target, window) {
                drifted.insert(window.id)
                guardAttempts[window.id, default: 0] += 1
                details.append("\(record.appName) \(window.id) \(rect(window.frame)) -> \(rect(target))")
            }
        }
        if !details.isEmpty {
            Log
                .info(
                    "Moved by macOS/app \(Int(now.timeIntervalSince(guardStart)))s after restoring (no user input); putting back: " +
                        details.joined(separator: "; ")
                )
        }
        return drifted
    }

    private func scheduleFlush() {
        flushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.store.flush() }
        flushWork = work
        queue.asyncAfter(deadline: .now() + Tuning.flushDelay, execute: work)
    }

    // MARK: - Restoring

    private struct PassResult {
        var moved = 0
        var failed: Set<CGWindowID> = []
        var spaceMismatches = 0
        var considered = 0
    }

    private func startRestore(
        layout: Layout,
        displays: [LiveDisplay],
        reason: String,
        only: Set<CGWindowID>? = nil,
        allowArrangement: Bool
    ) {
        cycle += 1
        let myCycle = cycle
        watchdogWork?.cancel()
        axElements.removeAll()
        setMode(.restoring, reason)

        if allowArrangement, Settings.fixArrangement, sawHotplug || sawSleepOrLock || reason == "manual",
           applyNextDisplayFix(layout: layout, displays: displays, reason: reason) {
            // The reconfiguration callbacks freeze and settle again; the next evaluation runs the
            // following fix step, and finally restores the windows.
            return
        }

        guard AX.isTrusted else {
            Log.info("No Accessibility permission: cannot move windows")
            lastRestore = "Accessibility permission missing"
            beginTracking()
            return
        }

        // macOS keeps nudging windows for a few seconds after displays come back, so run a few
        // cheap passes over what is visible (under the blur); each only touches windows that
        // drifted. Windows on other desktops are not visible, so they are handled afterwards,
        // with the blur already gone.
        restoreStartedAt = Date()
        let delays = Tuning.restorePassDelays
        func runPass(_ index: Int, moved: Int) {
            guard cycle == myCycle else { return }
            let current = store.layout(layout.profileID) ?? layout
            let result = restorePass(layout: current, only: only, deep: false, overlay: index == 0)
            let settled = index >= 1 && result.moved == 0
            if index + 1 < delays.count, !settled {
                queue.asyncAfter(deadline: .now() + (delays[index + 1] - delays[index])) {
                    runPass(index + 1, moved: moved + result.moved)
                }
                return
            }
            overlayDone()
            var final = restorePass(layout: current, only: only, deep: true, overlay: false)
            final.moved += moved + result.moved
            finishRestore(final, layout: current, only: only, reason: reason)
        }
        runPass(0, moved: 0)
    }

    private func overlayDone() {
        guard let shownAt = overlayShownAt else { return }
        let took = Date().timeIntervalSince(shownAt)
        Settings.overlayDuration = Settings.overlayDuration * 0.6 + took * 0.4
        overlayShownAt = nil
        DispatchQueue.main.async { RestoreOverlay.shared.finish() }
    }

    private func finishRestore(_ result: PassResult, layout: Layout, only: Set<CGWindowID>?, reason: String) {
        // Trust the window server, not the AX return codes: anything that is still not where
        // it belongs stays pending (its saved position is protected) and is retried when its
        // desktop is shown.
        let stillOff = offTarget(layout: layout, only: only)
        let expiry = Date().addingTimeInterval(Tuning.pendingExpiry)
        for id in result.failed.union(stillOff) {
            pending[id] = expiry
        }
        spaceMismatches = result.spaceMismatches
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        var summary = "\(formatter.string(from: Date())): \(result.moved) moved of \(result.considered)"
        if !pending.isEmpty {
            summary += ", \(pending.count) pending"
        }
        lastRestore = summary
        summary += String(format: " in %.1fs", Date().timeIntervalSince(restoreStartedAt))
        overlayDone()
        Log.info("Restore (\(reason)) \(summary); on another Space: \(result.spaceMismatches)")
        if !stillOff.isEmpty {
            Log.info("Not in place yet (will retry on their desktop): \(describe(stillOff, in: layout))")
        }
        // macOS (and some apps) can keep moving windows for a while after the displays come
        // back; for 3 minutes, changes nobody asked for are undone instead of saved.
        lastRestoreAt = Date()
        guardStart = Date()
        guardUntil = Date().addingTimeInterval(Tuning.guardDuration)
        guardAttempts.removeAll()
        beginTracking()
    }

    /// Re-tries windows that could not be restored, e.g. after the user switches to their desktop.
    private func restorePending() {
        guard mode == .tracking, !pending.isEmpty, let profile = activeProfileID,
              let layout = store.layout(profile) else { return }
        let ids = Set(pending.keys)
        let result = restorePass(layout: layout, only: ids, deep: false, overlay: false)
        guard result.moved > 0 || !result.failed.isEmpty else { return }
        // Check a moment later whether they stayed; give up on a window after a few visits so a
        // window an app refuses to move never blocks saving forever.
        queue.asyncAfter(deadline: .now() + Tuning.pendingVerifyDelay) { [weak self] in
            guard let self, self.mode == .tracking else { return }
            let current = self.store.layout(profile) ?? layout
            let stillOff = self.offTarget(layout: current, only: ids)
            var restored = 0
            for id in ids where self.pending[id] != nil {
                if stillOff.contains(id) {
                    let attempts = self.pendingAttempts[id, default: 0] + 1
                    self.pendingAttempts[id] = attempts
                    if attempts >= Tuning.pendingMaxAttempts {
                        self.pending.removeValue(forKey: id)
                        self.pendingAttempts.removeValue(forKey: id)
                        Log.info("Giving up on \(self.describe([id], in: current)); keeping where the app put it")
                    }
                } else if !Spaces.spaces(for: id).isEmpty {
                    self.pending.removeValue(forKey: id)
                    self.pendingAttempts.removeValue(forKey: id)
                    restored += 1
                }
            }
            if restored > 0 {
                Log.info("Restored \(restored) pending windows on their desktop")
            }
            self.publish()
        }
    }

    /// Windows (among `only`, or all) that exist, could be restored, and are not at their target.
    private func offTarget(layout: Layout, only: Set<CGWindowID>?) -> Set<CGWindowID> {
        let displays = Displays.current()
        let byKey = Dictionary(displays.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let savedDisplays = Dictionary(layout.displays.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let topology = Spaces.topology()
        let capture = WindowList.capture(topology: topology, ownPID: ownPID, apps: apps)
        var result: Set<CGWindowID> = []
        for record in layout.windows.values {
            if let only, !only.contains(record.windowID) {
                continue
            }
            if nonAXWindows.contains(record.windowID) {
                continue
            }
            guard let live = capture.byID[record.windowID], !record.fullscreen,
                  !live.spaces.contains(where: { topology.types[$0] == 4 }),
                  let display = byKey[record.displayKey] else { continue }
            let target = LayoutMath.targetFrame(record, saved: savedDisplays[record.displayKey], current: display)
            if !isAt(target, live) {
                result.insert(record.windowID)
            }
        }
        return result
    }

    /// Quick check (one window list read) used at unlock to decide whether to veil the screens.
    private func visibleWindowsLookMoved() -> Bool {
        let displays = Displays.current()
        guard Displays.hasExternal(displays), let layout = store.layout(Displays.profileID(displays)) else { return false }
        let byKey = Dictionary(displays.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let savedDisplays = Dictionary(layout.displays.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let topology = Spaces.topology()
        let capture = WindowList.capture(topology: topology, ownPID: ownPID, apps: apps)
        for record in layout.windows.values where !record.fullscreen && !nonAXWindows.contains(record.windowID) {
            guard let live = capture.byID[record.windowID], live.frame.height >= Tuning.minimumWindowSide,
                  !Set(live.spaces).isDisjoint(with: topology.active),
                  let display = byKey[record.displayKey] else { continue }
            if !live.frame.matches(LayoutMath.targetFrame(record, saved: savedDisplays[record.displayKey], current: display)) {
                return true
            }
        }
        return false
    }

    /// The app's own frame for a window, if it can be reached through Accessibility.
    private func axFrame(of window: LiveWindow) -> CGRect? {
        if let element = axElements[window.id], let frame = AX.frame(element) {
            return frame
        }
        guard let element = AX.elements(pid: window.pid, wanted: [window.id], deep: false)[window.id] else { return nil }
        if axElements.count > Tuning.elementCacheLimit {
            axElements.removeAll()
        }
        axElements[window.id] = element
        return AX.frame(element)
    }

    /// Whether a window really is at `target`. The window server's bounds can be mid-animation
    /// (Mission Control, swiping between desktops), so a mismatch is confirmed with the app.
    private func isAt(_ target: CGRect, _ window: LiveWindow) -> Bool {
        if window.frame.matches(target) {
            return true
        }
        return axFrame(of: window)?.matches(target) ?? false
    }

    private func rect(_ r: CGRect) -> String {
        "(\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height)))"
    }

    private func describe(_ ids: Set<CGWindowID>, in layout: Layout) -> String {
        ids.sorted().map { "\(layout.windows[String($0)]?.appName ?? "?") \($0)" }.joined(separator: ", ")
    }

    private func restorePass(layout: Layout, only: Set<CGWindowID>?, deep: Bool, overlay: Bool) -> PassResult {
        var result = PassResult()
        let displays = Displays.current()
        let byKey = Dictionary(displays.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let savedDisplays = Dictionary(layout.displays.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let topology = Spaces.topology()
        let capture = WindowList.capture(topology: topology, ownPID: ownPID, apps: apps)

        var jobs: [pid_t: [(CGWindowID, CGRect)]] = [:]
        for record in layout.windows.values {
            if let only, !only.contains(record.windowID) {
                continue
            }
            if nonAXWindows.contains(record.windowID) {
                continue
            }
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

            // Strips under 100 px (Chrome's tab-drag helpers and the like) are not real windows.
            if live.frame.height < Tuning.minimumWindowSide || live.frame.width < Tuning.minimumWindowSide {
                continue
            }
            let target = LayoutMath.targetFrame(record, saved: savedDisplays[record.displayKey], current: display)
            if live.frame.isClose(to: target) {
                continue
            }
            jobs[live.pid, default: []].append((record.windowID, target))
        }

        // Only veil the screens when there is actually something to put back.
        if overlay, !jobs.isEmpty, Settings.blurWhileRestoring, overlayShownAt == nil {
            overlayShownAt = Date()
            let estimate = Settings.overlayDuration
            DispatchQueue.main.async { RestoreOverlay.shared.show(estimate: estimate) }
        }

        // Phase 1 moves everything reachable cheaply (current desktop + cached elements);
        // phase 2 looks for windows on other desktops, in parallel across apps and skipping the
        // ones known to be unreachable, so slow apps never delay the rest.
        func apply(
            _ list: [(CGWindowID, CGRect)],
            pid: pid_t,
            elements: [CGWindowID: AXUIElement],
            onMissing: (CGWindowID, CGRect) -> Void
        ) {
            let app = AX.application(pid)
            for (id, target) in list {
                guard let element = elements[id] else {
                    onMissing(id, target)
                    continue
                }
                if AX.isMinimized(element) {
                    continue
                }
                if let current = AX.frame(element), current.matches(target) {
                    continue
                } // only looked off (animation)
                if AX.setFrame(element, app: app, to: target) {
                    result.moved += 1
                    knownUnreachable.remove(id)
                    if let live = capture.byID[id], Set(live.spaces).isDisjoint(with: topology.active) {
                        offSpaceWatch[id] = Watch(since: Date())
                    }
                } else {
                    axElements.removeValue(forKey: id)
                    result.failed.insert(id)
                }
            }
        }
        func isOnActiveDesktop(_ id: CGWindowID) -> Bool {
            capture.byID[id].map { !Set($0.spaces).isDisjoint(with: topology.active) } ?? true
        }

        var leftForDeep: [pid_t: [(CGWindowID, CGRect)]] = [:]
        for (pid, list) in jobs {
            let wanted = Set(list.map(\.0))
            var elements = axElements.filter { wanted.contains($0.key) }
            let missing = wanted.subtracting(elements.keys)
            if !missing.isEmpty {
                let found = AX.elements(pid: pid, wanted: missing, deep: false)
                elements.merge(found) { a, _ in a }
                axElements.merge(found) { a, _ in a }
            }
            apply(list, pid: pid, elements: elements) { id, target in
                if isOnActiveDesktop(id) {
                    nonAXWindows.insert(id) // visible yet not an AX window: nothing to move
                } else if deep && !knownUnreachable.contains(id) {
                    leftForDeep[pid, default: []].append((id, target))
                } else {
                    result.failed.insert(id) // retried when its desktop is shown
                }
            }
        }

        if !leftForDeep.isEmpty {
            let work = Array(leftForDeep)
            let lock = NSLock()
            var foundByPid: [pid_t: [CGWindowID: AXUIElement]] = [:]
            DispatchQueue.concurrentPerform(iterations: work.count) { i in
                let (pid, list) = work[i]
                let found = AX.elements(pid: pid, wanted: Set(list.map(\.0)), deep: true, budget: Tuning.deepScanBudget)
                lock.lock()
                foundByPid[pid] = found
                lock.unlock()
            }
            for (pid, list) in work {
                let found = foundByPid[pid] ?? [:]
                axElements.merge(found) { a, _ in a }
                apply(list, pid: pid, elements: found) { id, _ in
                    knownUnreachable.insert(id)
                    result.failed.insert(id)
                }
            }
        }
        return result
    }

    /// After a reboot or an app relaunch the window ids change. Match the saved records to the
    /// new windows of the same app by title (or when the app has exactly one window).
    private func rebindDeadRecords(profile: String) -> Set<CGWindowID> {
        guard var layout = store.layout(profile) else { return [] }
        let capture = WindowList.capture(topology: Spaces.topology(), ownPID: ownPID, apps: apps)
        let dead = layout.windows.values.filter { !capture.existing.contains($0.windowID) }
        guard !dead.isEmpty else { return [] }

        let known = Set(layout.windows.values.map(\.windowID))
        var candidates: [String: [LiveWindow]] = [:]
        for window in capture.trackable where !known.contains(window.id) {
            if let bundle = apps.info(window.pid).bundleID {
                candidates[bundle, default: []].append(window)
            }
        }
        guard !candidates.isEmpty else {
            layout.windows = layout.windows.filter { capture.existing.contains($0.value.windowID) }
            store.put(layout)
            return []
        }

        // Titles of the new windows (CGWindowList only has them with Screen Recording permission).
        // Apps are scanned in parallel: a slow one must not delay the launch by its whole budget.
        var liveTitles: [CGWindowID: String] = [:]
        if AX.isTrusted {
            let groups = Array(candidates.values)
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: groups.count) { i in
                let windows = groups[i]
                guard let pid = windows.first?.pid else { return }
                var found: [CGWindowID: String] = [:]
                for (id, element) in AX.elements(pid: pid, wanted: Set(windows.map(\.id)), deep: true) {
                    if let title = AX.title(element) {
                        found[id] = title
                    }
                }
                lock.lock()
                liveTitles.merge(found) { a, _ in a }
                lock.unlock()
            }
        }

        var rebound: Set<CGWindowID> = []
        for (record, window) in LayoutMath.rebind(dead: dead, candidates: candidates, titles: liveTitles) {
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
        if let id = activeProfileID {
            status.windowCount = store.layout(id)?.windows.count ?? 0
        }
        status.profiles = store.layouts.values
            .filter { $0.displays.contains { !$0.isBuiltin } }
            .map {
                ProfileSummary(
                    id: $0.profileID,
                    name: Displays.profileName($0.displays),
                    windowCount: $0.windows.count,
                    updatedAt: $0.updatedAt,
                    isActive: $0.profileID == activeProfileID
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }
        statusLock.lock()
        _status = status
        statusLock.unlock()
        DispatchQueue.main.async { [weak self] in self?.onStatusChange?() }
    }
}
