import AppKit
import Carbon
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var trustTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        Engine.shared.onStatusChange = { [weak self] in self?.updateIcon() }
        SystemEvents.shared.install()

        let mods = controlKey | optionKey | cmdKey
        HotKeys.shared.register(keyCode: kVK_ANSI_R, modifiers: mods) { Engine.shared.restoreNow() }
        HotKeys.shared.register(keyCode: kVK_ANSI_S, modifiers: mods) { Engine.shared.saveNow() }

        if !AX.isTrusted {
            AX.promptForTrust()
            trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                guard AX.isTrusted else { return }
                timer.invalidate()
                self?.trustTimer = nil
                Engine.shared.accessibilityGranted()
            }
            trustTimer?.tolerance = 1
        }

        Engine.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Engine.shared.flushSync()
    }

    // MARK: - Status item

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let status = Engine.shared.status
        let symbol: String
        switch status.mode {
        case .tracking: symbol = "rectangle.split.2x1"
        case .restoring: symbol = "arrow.triangle.2.circlepath"
        case .frozen: symbol = "moon.zzz"
        case .paused: symbol = "pause.rectangle"
        case .inactive, .starting: symbol = "laptopcomputer"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "ManyDisplays")
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = status.mode == .inactive || status.mode == .paused
        button.toolTip = "ManyDisplays: \(describe(status))"
    }

    private func describe(_ status: Engine.Status) -> String {
        switch status.mode {
        case .starting: return "Starting…"
        case .inactive: return "Idle: no external displays"
        case .tracking: return "Tracking \(status.windowCount) windows"
        case .frozen: return "On hold: \(status.detail)"
        case .restoring: return "Restoring windows…"
        case .paused: return "Paused"
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
        if let restore = status.lastRestore { menu.addItem(disabled("Last restore: \(restore)")) }
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
        restore.keyEquivalent = "r"
        restore.keyEquivalentModifierMask = [.control, .option, .command]
        menu.addItem(restore)
        let save = item("Save Positions Now", #selector(saveNow))
        save.keyEquivalent = "s"
        save.keyEquivalentModifierMask = [.control, .option, .command]
        menu.addItem(save)

        menu.addItem(.separator())
        let pause = item("Pause Tracking", #selector(togglePause))
        pause.state = Settings.paused ? .on : .off
        menu.addItem(pause)
        let arrangement = item("Restore Display Arrangement & Resolution", #selector(toggleArrangement))
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
        if status.profiles.isEmpty { profilesMenu.addItem(disabled("None yet")) }
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
        menu.addItem(item("Quit ManyDisplays", #selector(quit)))
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

    @objc private func restoreNow() { Engine.shared.restoreNow() }
    @objc private func saveNow() { Engine.shared.saveNow() }
    @objc private func togglePause() { Engine.shared.setPaused(!Settings.paused) }
    @objc private func toggleArrangement() { Settings.fixArrangement.toggle() }
    @objc private func toggleBlur() { Settings.blurWhileRestoring.toggle() }

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

    @objc private func openData() { NSWorkspace.shared.open(LayoutStore.directory) }
    @objc private func openLog() { NSWorkspace.shared.open(Log.url) }
    @objc private func quit() { NSApp.terminate(nil) }
}
