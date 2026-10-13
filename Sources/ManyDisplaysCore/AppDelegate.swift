import AppKit
import Carbon
import ServiceManagement
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var trustTimer: Timer?
    /// Sparkle, only when the bundle carries a feed URL and public key (release builds).
    private var updater: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil,
           Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil {
            updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        Engine.shared.onStatusChange = { [weak self] in self?.updateIcon() }
        SystemEvents.shared.install()

        if let spec = Settings.restoreHotKey {
            HotKeys.shared.register(spec) { Engine.shared.restoreNow() }
        }
        if let spec = Settings.saveHotKey {
            HotKeys.shared.register(spec) { Engine.shared.saveNow() }
        }

        if !AX.isTrusted {
            AX.promptForTrust()
            trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                guard AX.isTrusted else { return }
                timer.invalidate()
                self?.trustTimer = nil
                UserInput.startMonitoring()
                Engine.shared.accessibilityGranted()
            }
            trustTimer?.tolerance = 1
        }

        UserInput.startMonitoring()
        Engine.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Engine.shared.flushSync()
    }

    // MARK: - Status item

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let status = Engine.shared.status
        let image: NSImage? = switch status.mode {
        case .tracking: StatusIcon.displays(accessibilityDescription: AppIdentity.name)
        case .restoring: symbol("arrow.triangle.2.circlepath")
        case .frozen: symbol("moon.zzz")
        case .paused: symbol("pause.rectangle")
        case .inactive, .starting: symbol("laptopcomputer")
        }
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = status.mode == .inactive || status.mode == .paused
        button.toolTip = "\(AppIdentity.name): \(describe(status))"
    }

    private func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: AppIdentity.name)
    }

    private func describe(_ status: Engine.Status) -> String {
        switch status.mode {
        case .starting: "Starting…"
        case .inactive: "Idle: no external displays"
        case .tracking: "Tracking \(status.windowCount) windows"
        case .frozen: "On hold: \(status.detail)"
        case .restoring: "Restoring windows…"
        case .paused: "Paused"
        }
    }

    // MARK: - Menu (rebuilt only when opened)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = Engine.shared.status

        menu.addItem(disabled(describe(status)))
        if let save = status.lastSave {
            let relative = RelativeDateTimeFormatter()
            relative.unitsStyle = .short
            menu.addItem(disabled("Last saved: \(relative.localizedString(for: save, relativeTo: Date()))"))
        }
        if let restore = status.lastRestore {
            menu.addItem(disabled("Last restore: \(restore)"))
        }
        if status.pending > 0 {
            menu.addItem(disabled("\(status.pending) windows will be restored when you visit their Space"))
        }
        if status.spaceMismatches > 0 {
            menu.addItem(disabled("⚠︎ \(status.spaceMismatches) windows are on a different Space"))
        }
        if !AX.isTrusted {
            menu.addItem(.separator())
            menu.addItem(item("Grant Accessibility Permission…", #selector(openAccessibility)))
        }

        menu.addItem(.separator())
        let restore = item("Restore Windows Now", #selector(restoreNow))
        applyShortcut(Settings.restoreHotKey, to: restore)
        menu.addItem(restore)
        let save = item("Save Positions Now", #selector(saveNow))
        applyShortcut(Settings.saveHotKey, to: save)
        menu.addItem(save)

        menu.addItem(.separator())
        let pause = item("Pause Tracking", #selector(togglePause))
        pause.state = Settings.paused ? .on : .off
        menu.addItem(pause)
        let arrangement = item("Restore Display Setup After Wake", #selector(toggleArrangement))
        arrangement.state = Settings.fixArrangement ? .on : .off
        menu.addItem(arrangement)
        let blur = item("Blur Screens While Restoring", #selector(toggleBlur))
        blur.state = Settings.blurWhileRestoring ? .on : .off
        menu.addItem(blur)
        let login = item("Open at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let profilesItem = NSMenuItem(title: "Saved Display Setups", action: nil, keyEquivalent: "")
        let profilesMenu = NSMenu()
        if status.profiles.isEmpty {
            profilesMenu.addItem(disabled("None yet"))
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        for profile in status.profiles {
            let entry = NSMenuItem(title: profile.name, action: nil, keyEquivalent: "")
            entry.state = profile.isActive ? .on : .off
            let sub = NSMenu()
            sub.addItem(disabled("\(profile.windowCount) windows · \(formatter.string(from: profile.updatedAt))"))
            let forget = item("Forget This Setup", #selector(forgetProfile(_:)))
            forget.representedObject = profile.id
            sub.addItem(forget)
            entry.submenu = sub
            profilesMenu.addItem(entry)
        }
        profilesItem.submenu = profilesMenu
        menu.addItem(profilesItem)
        menu.addItem(item("Open Data Folder", #selector(openData)))
        menu.addItem(item("Show Log", #selector(openLog)))

        menu.addItem(.separator())
        menu.addItem(disabled("\(AppIdentity.name) \(AppIdentity.version)"))
        if let updater {
            let check = NSMenuItem(
                title: "Check for Updates…",
                action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                keyEquivalent: ""
            )
            check.target = updater
            menu.addItem(check)
        }
        menu.addItem(item("Quit \(AppIdentity.name)", #selector(quit)))
    }

    /// Shows the global shortcut next to the menu item (the Carbon hot key does the real work).
    private func applyShortcut(_ spec: HotKeySpec?, to item: NSMenuItem) {
        guard let spec else { return }
        item.keyEquivalent = spec.key
        var mask: NSEvent.ModifierFlags = []
        if spec.modifiers & controlKey != 0 {
            mask.insert(.control)
        }
        if spec.modifiers & optionKey != 0 {
            mask.insert(.option)
        }
        if spec.modifiers & cmdKey != 0 {
            mask.insert(.command)
        }
        if spec.modifiers & shiftKey != 0 {
            mask.insert(.shift)
        }
        item.keyEquivalentModifierMask = mask
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func restoreNow() {
        Engine.shared.restoreNow()
    }

    @objc private func saveNow() {
        Engine.shared.saveNow()
    }

    @objc private func togglePause() {
        Engine.shared.setPaused(!Settings.paused)
    }

    @objc private func toggleArrangement() {
        Settings.fixArrangement.toggle()
    }

    @objc private func toggleBlur() {
        Settings.blurWhileRestoring.toggle()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Log.info("Could not change login item: \(error)")
        }
    }

    @objc private func forgetProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Engine.shared.forgetProfile(id)
    }

    @objc private func openAccessibility() {
        AX.promptForTrust()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openData() {
        NSWorkspace.shared.open(LayoutStore.directory)
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(Log.url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
