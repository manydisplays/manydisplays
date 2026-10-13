import AppKit

/// Settings → Keyboard Shortcuts…: one recorder per action. Click a field, press the combination;
/// Delete clears it (no shortcut), Escape cancels. Changes apply immediately. Main thread.
final class ShortcutsWindow: NSObject, NSWindowDelegate {
    static let shared = ShortcutsWindow()

    private var window: NSWindow?
    private var recorders: [ShortcutRecorder] = []

    func show() {
        if window == nil {
            build()
        }
        recorders.forEach { $0.refresh() }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 170),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Keyboard Shortcuts"
        w.isReleasedWhenClosed = false
        w.delegate = self

        let rows = NSGridView()
        rows.rowSpacing = 10
        rows.columnSpacing = 12
        for (title, key) in [("Restore windows now", "restoreHotKey"), ("Save current layout", "saveHotKey")] {
            let label = NSTextField(labelWithString: title)
            let recorder = ShortcutRecorder(settingsKey: key)
            recorders.append(recorder)
            let clear = NSButton(title: "Clear", target: recorder, action: #selector(ShortcutRecorder.clear))
            clear.bezelStyle = .rounded
            rows.addRow(with: [label, recorder, clear])
        }
        rows.column(at: 0).xPlacement = .trailing
        let hint =
            NSTextField(
                wrappingLabelWithString: "Click a field and press the keys. Shortcuts work in every app; use ⌃, ⌥ or ⌘ plus a letter, a digit or an F key."
            )
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)

        let stack = NSStackView(views: [rows, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        w.contentView = stack
        NSLayoutConstraint.activate([hint.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40)])
        window = w
    }
}

/// A field that records one key combination.
final class ShortcutRecorder: NSView {
    private let settingsKey: String
    private let label = NSTextField(labelWithString: "")
    private var recording = false {
        didSet { refresh() }
    }

    init(settingsKey: String) {
        self.settingsKey = settingsKey
        super.init(frame: NSRect(x: 0, y: 0, width: 160, height: 26))
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        label.alignment = .center
        label.font = .systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 160),
            heightAnchor.constraint(equalToConstant: 26),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private var current: HotKeySpec? {
        settingsKey == "restoreHotKey" ? Settings.restoreHotKey : Settings.saveHotKey
    }

    func refresh() {
        layer?.borderColor = (recording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        if recording {
            label.stringValue = "Press keys…"
            label.textColor = .controlAccentColor
        } else if let spec = current {
            label.stringValue = spec.display
            label.textColor = .labelColor
        } else {
            label.stringValue = "None"
            label.textColor = .tertiaryLabelColor
        }
    }

    @objc func clear() {
        Settings.setHotKey(settingsKey, text: "")
        HotKeys.reloadFromSettings()
        recording = false
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self); recording = true
    }

    override func becomeFirstResponder() -> Bool {
        recording = true; return true
    }

    override func resignFirstResponder() -> Bool {
        recording = false; return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        switch Int(event.keyCode) {
        case 53: // Escape
            window?.makeFirstResponder(nil)
        case 51, 117: // Delete, Forward delete
            clear()
        default:
            guard let text = HotKeySpec.text(keyCode: Int(event.keyCode), flags: event.modifierFlags), HotKeySpec(text) != nil
            else { NSSound.beep(); return }
            Settings.setHotKey(settingsKey, text: text)
            HotKeys.reloadFromSettings()
            window?.makeFirstResponder(nil)
        }
    }

    // Modifier-only presses must not trigger the text field's "no handler" beep.
    override func flagsChanged(with event: NSEvent) {}
}

extension HotKeys {
    /// Re-registers both shortcuts from Settings (after the user changed them).
    static func reloadFromSettings() {
        shared.unregisterAll()
        if let spec = Settings.restoreHotKey {
            shared.register(spec) { Engine.shared.restoreNow() }
        }
        if let spec = Settings.saveHotKey {
            shared.register(spec) { Engine.shared.saveNow() }
        }
    }
}
