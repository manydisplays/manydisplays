import AppKit
import ApplicationServices
import Carbon

/// Event-driven window tracking: one AXObserver per regular app. No polling; moves, resizes,
/// new windows and closes just schedule a (debounced) snapshot on the engine. Main thread only.
final class AXHub {
    static let shared = AXHub()

    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []
    private var running = false

    private static let appNotifications = [
        kAXWindowCreatedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification,
        kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
        kAXFocusedWindowChangedNotification, kAXTitleChangedNotification,
        kAXApplicationHiddenNotification, kAXApplicationShownNotification,
    ]
    private static let windowNotifications = [
        kAXUIElementDestroyedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification,
        kAXTitleChangedNotification,
    ]

    func start() {
        guard !running, AX.isTrusted else { return }
        running = true
        for app in NSWorkspace.shared.runningApplications {
            add(app)
        }
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens = [
            center
                .addObserver(
                    forName: NSWorkspace.didLaunchApplicationNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] note in
                    guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                    self?.add(app)
                    Engine.shared.windowEvent()
                },
            center
                .addObserver(
                    forName: NSWorkspace.didTerminateApplicationNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] note in
                    guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                    self?.remove(app.processIdentifier)
                    Engine.shared.windowEvent()
                },
        ]
        Log.info("Observing \(observers.count) apps")
    }

    func stop() {
        guard running else { return }
        running = false
        workspaceTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceTokens.removeAll()
        for pid in Array(observers.keys) {
            remove(pid)
        }
    }

    private func add(_ app: NSRunningApplication, attempt: Int = 0) {
        let pid = app.processIdentifier
        guard running, app.activationPolicy == .regular, pid != getpid(), observers[pid] == nil,
              !app.isTerminated else { return }

        var created: AXObserver?
        guard AXObserverCreate(pid, axCallback, &created) == .success, let observer = created else { return }
        let element = AX.application(pid, timeout: 0.3)
        var registered = false
        for name in Self.appNotifications {
            if AXObserverAddNotification(observer, element, name as CFString, nil) == .success {
                registered = true
            }
        }
        guard registered else {
            // Freshly launched apps are often not ready for AX yet.
            if attempt < 3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempt + 1) * 1.5) { [weak self] in
                    self?.add(app, attempt: attempt + 1)
                }
            }
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
        for window in AX.standardWindows(element) {
            observeWindow(window, observer: observer)
            Engine.shared.windowTitleMaybeChanged(window)
        }
    }

    private func remove(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private func observeWindow(_ window: AXUIElement, observer: AXObserver) {
        for name in Self.windowNotifications {
            AXObserverAddNotification(observer, window, name as CFString, nil)
        }
    }

    fileprivate func handle(observer: AXObserver, element: AXUIElement, notification: String) {
        switch notification {
        case kAXWindowCreatedNotification:
            observeWindow(element, observer: observer)
            Engine.shared.windowTitleMaybeChanged(element)
            Engine.shared.windowEvent()
        case kAXTitleChangedNotification, kAXFocusedWindowChangedNotification:
            Engine.shared.windowTitleMaybeChanged(element)
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            Engine.shared.windowMoved(element, byUser: UserInput.happened(within: 1.5))
        default:
            Engine.shared.windowEvent()
        }
    }
}

private let axCallback: AXObserverCallback = { observer, element, notification, _ in
    AXHub.shared.handle(observer: observer, element: element, notification: notification as String)
}

/// Commands the command-line flags send to the running instance. Distributed notifications
/// can be posted by any process of the same user; the commands carry no payload and only do
/// what the menu does, so the worst a rogue process can do is trigger a save or a restore.
enum RemoteCommand {
    static let save = Notification.Name(AppIdentity.bundleID + ".save")
    static let restore = Notification.Name(AppIdentity.bundleID + ".restore")
    static let previewOverlay = Notification.Name(AppIdentity.bundleID + ".previewOverlay")
}

/// System-wide signals: display reconfiguration, sleep/wake, lock/unlock, space changes.
/// These stay installed always; they cost nothing while idle.
final class SystemEvents {
    static let shared = SystemEvents()
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    func install() {
        DisplayNames.refresh()

        CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            if flags.contains(.beginConfigurationFlag) {
                Engine.shared.displayReconfigBegan()
            } else {
                let hotplug = flags.contains(.addFlag) || flags.contains(.removeFlag)
                    || flags.contains(.enabledFlag) || flags.contains(.disabledFlag)
                Engine.shared.displayReconfigEnded(hotplug: hotplug)
            }
        }, nil)

        let ws = NSWorkspace.shared.notificationCenter
        observe(ws, NSWorkspace.willSleepNotification) { Engine.shared.willSleep() }
        observe(ws, NSWorkspace.didWakeNotification) { Engine.shared.didWake() }
        observe(ws, NSWorkspace.screensDidSleepNotification) { Engine.shared.screensDidSleep() }
        observe(ws, NSWorkspace.screensDidWakeNotification) { Engine.shared.screensDidWake() }
        observe(ws, NSWorkspace.sessionDidResignActiveNotification) { Engine.shared.screenLockChanged(locked: true) }
        observe(ws, NSWorkspace.sessionDidBecomeActiveNotification) { Engine.shared.screenLockChanged(locked: false) }
        observe(ws, NSWorkspace.activeSpaceDidChangeNotification) { Engine.shared.activeSpaceChanged() }

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { Engine.shared.screenLockChanged(locked: true) }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { Engine.shared.screenLockChanged(locked: false) }

        observe(distributed, RemoteCommand.save) { Engine.shared.saveNow() }
        observe(distributed, RemoteCommand.restore) { Engine.shared.restoreNow() }
        observe(distributed, RemoteCommand.previewOverlay) {
            // Countdown with the learned estimate, then the "Done" state.
            let estimate = Settings.overlayDuration
            RestoreOverlay.shared.show(estimate: estimate)
            DispatchQueue.main.asyncAfter(deadline: .now() + estimate + 0.3) { RestoreOverlay.shared.finish() }
        }

        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { DisplayNames.refresh() }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ block: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in block() }
        tokens.append((center, token))
    }
}

/// Global shortcuts through Carbon (no extra permissions needed).
final class HotKeys {
    static let shared = HotKeys()
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var installed = false

    func register(_ spec: HotKeySpec, _ handler: @escaping () -> Void) {
        if !installed {
            install()
        }
        let id = UInt32(handlers.count + 1)
        handlers[id] = handler
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D44_5350), id: id)
        if RegisterEventHotKey(UInt32(spec.keyCode), UInt32(spec.modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref) ==
            noErr,
            let ref {
            refs.append(ref)
        } else {
            Log.info("Could not register the global shortcut (already taken by another app?)")
        }
    }

    private func install() {
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            HotKeys.shared.handlers[hotKeyID.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }
}
