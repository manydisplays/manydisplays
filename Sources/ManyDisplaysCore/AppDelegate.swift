import AppKit
import Carbon
import ServiceManagement
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, SPUUpdaterDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var trustTimer: Timer?
    /// The Accessibility permission as last seen; polled so a grant or a revocation is noticed
    /// while running (every 2 s while missing, every 10 s once granted).
    private var trusted = AX.isTrusted
    /// Sparkle, only when the bundle carries a feed URL and public key (release builds).
    private var updater: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil,
           Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil {
            updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        }
        Licensing.shared.onChange = { [weak self] in self?.updateIcon() }
        installEditMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        Engine.shared.onStatusChange = { [weak self] in self?.updateIcon() }
        SystemEvents.shared.install()

        HotKeys.reloadFromSettings()

        AccessibilityWindow.shared.checkTrust = { [weak self] in self?.checkTrust() }
        // Our own explanation first; the system prompt only comes after Grant Access.
        if !trusted, AccessibilityWindow.shared.shouldShowOnLaunch {
            AccessibilityWindow.shared.show()
        }
        scheduleTrustCheck()

        UserInput.startMonitoring()
        Engine.shared.start()
    }

    // MARK: - Accessibility permission

    private func scheduleTrustCheck() {
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: trusted ? 10 : 2, repeats: true) { [weak self] _ in
            self?.checkTrust()
        }
        trustTimer?.tolerance = 1
    }

    /// Picks up a grant or a revocation; both take effect without a restart.
    private func checkTrust() {
        let now = AX.isTrusted
        guard now != trusted else { return }
        trusted = now
        if now {
            UserInput.startMonitoring()
            Engine.shared.accessibilityGranted()
            AccessibilityWindow.shared.permissionGranted()
        } else {
            UserInput.stopMonitoring()
            Engine.shared.accessibilityRevoked()
        }
        scheduleTrustCheck()
        updateIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Engine.shared.flushSync()
    }

    /// A menu bar app has no main menu, so ⌘C/⌘V/⌘A would not reach its text fields (the licence
    /// window) without this invisible Edit menu.
    private func installEditMenu() {
        let main = NSMenu()
        let edit = NSMenuItem()
        main.addItem(edit)
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = menu
        NSApp.mainMenu = main
    }

    // MARK: - Status item

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let status = Engine.shared.status
        // Always the app's face; the state is told by dimming (idle, paused, no permission) and
        // by the tooltip/menu.
        button.image = StatusIcon.displays(accessibilityDescription: "\(AppIdentity.name): \(describe(status))")
        button.appearsDisabled = !trusted || status.mode == .inactive || status.mode == .paused
        button.toolTip = "\(AppIdentity.name): \(describe(status))"
    }

    private func describe(_ status: Engine.Status) -> String {
        if !trusted {
            return "Accessibility permission needed"
        }
        return switch status.mode {
        case .starting: "Starting…"
        case .inactive: "Idle: no external displays"
        case .tracking: "Remembering \(status.windowCount) windows"
        case .frozen: "On hold: \(status.detail)"
        case .restoring: "Restoring windows…"
        case .paused: "Paused"
        }
    }

    // MARK: - Menu (rebuilt only when opened)

    func menuNeedsUpdate(_ menu: NSMenu) {
        checkTrust()
        menu.removeAllItems()
        let status = Engine.shared.status

        // What matters right now: state, anything the user must act on, and the trial.
        menu.addItem(statusLine(status))
        if status.pending > 0 {
            menu.addItem(disabled("\(status.pending) windows will be restored when you visit their Space"))
        }
        if status.spaceMismatches > 0 {
            menu.addItem(disabled("⚠︎ \(status.spaceMismatches) windows are on a different Space"))
        }
        if !trusted {
            menu.addItem(disabled("Without it, positions are saved but windows cannot be moved"))
            menu.addItem(item("Grant Accessibility Permission…", #selector(openAccessibility), symbol: "lock.open"))
        }
        addTrialItems(to: menu)

        menu.addItem(.separator())
        let restore = item("Restore Windows Now", #selector(restoreNow), symbol: "arrow.counterclockwise")
        applyShortcut(Settings.restoreHotKey, to: restore)
        menu.addItem(restore)
        let save = item("Save Current Layout", #selector(saveNow), symbol: "square.and.arrow.down")
        save.toolTip = "Positions are saved automatically; use this to make what you see now the saved layout."
        applyShortcut(Settings.saveHotKey, to: save)
        menu.addItem(save)
        let pause = item(
            Settings.paused ? "Resume \(AppIdentity.name)" : "Pause \(AppIdentity.name)",
            #selector(togglePause),
            symbol: Settings.paused ? "play.fill" : "pause.fill"
        )
        menu.addItem(pause)

        menu.addItem(.separator())
        menu.addItem(submenu("Saved Display Setups", savedSetupsMenu(status), symbol: "display.2"))
        menu.addItem(submenu("Settings", settingsMenu(), symbol: "gearshape"))
        menu.addItem(submenu("Help", helpMenu(status), symbol: "questionmark.circle"))
        if let updater {
            let check = NSMenuItem(
                title: "Check for Updates…",
                action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                keyEquivalent: ""
            )
            check.target = updater
            check.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
            menu.addItem(check)
        }

        menu.addItem(.separator())
        menu.addItem(item("About \(AppIdentity.name)…", #selector(openWebsite), symbol: "info.circle"))
        menu.addItem(item("Quit \(AppIdentity.name)", #selector(quit), symbol: "power"))
    }

    /// Trial and licence prompts stay at the top until the app is licensed.
    private func addTrialItems(to menu: NSMenu) {
        switch Licensing.shared.state {
        case .free, .licensed: return
        case let .trial(days):
            menu.addItem(.separator())
            menu.addItem(disabled("Trial: \(days) day\(days == 1 ? "" : "s") left"))
            menu.addItem(item("Buy \(AppIdentity.name)…", #selector(buy), symbol: "cart"))
            menu.addItem(item("Enter Licence…", #selector(enterLicense), symbol: "key"))
        case .trialExpired:
            menu.addItem(.separator())
            menu.addItem(item("Buy \(AppIdentity.name)…", #selector(buy), symbol: "cart"))
            menu.addItem(item("Enter Licence…", #selector(enterLicense), symbol: "key"))
        case .updatesExpired:
            menu.addItem(.separator())
            menu.addItem(item("Renew Licence…", #selector(buy), symbol: "cart"))
            menu.addItem(item("Enter Licence…", #selector(enterLicense), symbol: "key"))
        }
    }

    private func savedSetupsMenu(_ status: Engine.Status) -> NSMenu {
        let menu = NSMenu()
        if status.profiles.isEmpty {
            menu.addItem(disabled("None yet"))
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
            menu.addItem(entry)
        }
        return menu
    }

    private func settingsMenu() -> NSMenu {
        let menu = NSMenu()
        let auto = item("Restore Windows Automatically", #selector(toggleAutoRestore))
        auto.state = Settings.autoRestore ? .on : .off
        auto.toolTip = "Off: after wake, unlock or reconnecting displays, nothing moves until you choose Restore Windows Now."
        menu.addItem(auto)
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
        menu.addItem(item("Keyboard Shortcuts…", #selector(showShortcuts), symbol: "keyboard"))
        menu.addItem(item("Reset Settings to Defaults…", #selector(resetSettings), symbol: "arrow.uturn.backward"))
        return menu
    }

    private func helpMenu(_ status: Engine.Status) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(disabled("\(AppIdentity.name) \(AppIdentity.version)"))
        switch Licensing.shared.state {
        case .free: break
        case let .licensed(key):
            menu.addItem(disabled("Licensed to \(key.email)"))
            menu.addItem(item("Licence…", #selector(enterLicense), symbol: "key"))
        default:
            menu.addItem(item("Enter Licence…", #selector(enterLicense), symbol: "key"))
        }
        menu.addItem(.separator())
        if let save = status.lastSave {
            let relative = RelativeDateTimeFormatter()
            relative.unitsStyle = .short
            menu.addItem(disabled("Last saved: \(relative.localizedString(for: save, relativeTo: Date()))"))
        }
        if let restore = status.lastRestore {
            menu.addItem(disabled("Last restore: \(restore)"))
        }
        menu.addItem(item("Support Website…", #selector(openSupport), symbol: "globe"))
        menu.addItem(item("Show Log", #selector(openLog), symbol: "doc.text"))
        menu.addItem(item("Open Data Folder", #selector(openData), symbol: "folder"))
        return menu
    }

    private func submenu(_ title: String, _ menu: NSMenu, symbol: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.submenu = menu
        entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return entry
    }

    @objc private func openSupport() {
        NSWorkspace.shared.open(URL(string: "https://manydisplays.com/support")!)
    }

    @objc private func buy() {
        NSWorkspace.shared.open(Licensing.buyURL)
    }

    @objc private func enterLicense() {
        LicenseWindow.shared.show()
    }

    // MARK: - Sparkle

    /// Updates published after the licence's update window are not offered; the current
    /// version keeps working.
    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        guard Licensing.shared.required, let key = Licensing.shared.key, let published = updateItem.date,
              published > key.updatesUntil else { return }
        let until = key.updatesUntil
        throw NSError(domain: AppIdentity.bundleID, code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Version \(updateItem.displayVersionString) was released after your licence's update window (\(Licensing.string(until))). Renew your licence to get it.",
        ])
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

    private func item(_ title: String, _ action: Selector, symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        return item
    }

    /// The status line: a coloured dot like Docker's, green while tracking.
    private func statusLine(_ status: Engine.Status) -> NSMenuItem {
        var text = describe(status)
        var colour: NSColor = switch status.mode {
        case .tracking: .systemGreen
        case .restoring: .systemOrange
        case .frozen, .starting: .systemYellow
        case .inactive, .paused: .systemGray
        }
        switch Licensing.shared.state {
        case _ where !trusted:
            colour = .systemOrange
        case .trialExpired:
            text = "Trial over: \(status.windowCount) windows remembered, not restored"
            colour = .systemOrange
        case .updatesExpired:
            text = "Licence does not cover this version: windows not restored"
            colour = .systemOrange
        default: break
        }
        let item = disabled(text)
        item.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [colour]))
        return item
    }

    @objc private func resetSettings() {
        let alert = NSAlert()
        alert.messageText = "Reset settings to defaults?"
        alert.informativeText = "Automatic restore, display fixes and the blur go back on, the app resumes if it was paused, and the shortcuts return to ⌃⌥⌘R. Your licence, saved layouts and the login item are kept."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let wasPaused = Settings.paused
        Settings.resetToDefaults()
        HotKeys.reloadFromSettings()
        if wasPaused {
            Engine.shared.setPaused(false)
        }
        Log.info("Settings reset to defaults")
        updateIcon()
    }

    @objc private func showShortcuts() {
        ShortcutsWindow.shared.show()
    }

    @objc private func openWebsite() {
        NSWorkspace.shared.open(URL(string: "https://manydisplays.com")!)
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

    @objc private func toggleAutoRestore() {
        Engine.shared.setAutoRestore(!Settings.autoRestore)
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
        AccessibilityWindow.shared.show()
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
