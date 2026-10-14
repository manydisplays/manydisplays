import AppKit

/// The welcome window: explains the Accessibility permission before macOS asks for it. Three
/// looks: the welcome with Grant Access / Not Now, "almost there" once the user went on to System
/// Settings, and a short "all set" when the permission arrives (then it closes itself). Main thread.
final class AccessibilityWindow: NSObject, NSWindowDelegate {
    static let shared = AccessibilityWindow()

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    private enum Look {
        case welcome, waiting, granted
    }

    private var window: NSWindow?
    private var look = Look.welcome
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(wrappingLabelWithString: "")
    private let points = NSStackView()
    private let footnote = NSTextField(wrappingLabelWithString: "")
    private let notNow = NSButton(title: "Not Now", target: nil, action: nil)
    private let primary = NSButton(title: "Grant Access", target: nil, action: nil)

    /// On launch: unless the user chose Not Now for this version (an update shows it once more).
    var shouldShowOnLaunch: Bool {
        Settings.accessibilityNotNowVersion != AppIdentity.version
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func show() {
        if window == nil {
            build()
        }
        refresh(.welcome)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Called when the permission arrives: a moment of "all set", then the window goes away.
    func permissionGranted() {
        Settings.accessibilityNotNowVersion = nil
        guard isVisible else { return }
        refresh(.granted)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard self?.look == .granted else { return }
            self?.window?.close()
        }
    }

    private func build() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.delegate = self

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.alignment = .center
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        footnote.font = .systemFont(ofSize: 11)
        footnote.textColor = .secondaryLabelColor
        footnote.alignment = .center

        points.orientation = .vertical
        points.alignment = .leading
        points.spacing = 12
        for (symbol, heading, line) in [
            (
                "macwindow.on.rectangle",
                "Windows back where they were",
                "After sleep, lock or plugging your monitors back in."
            ),
            (
                "hand.raised",
                "One permission: Accessibility",
                "macOS needs it before any app can move other apps' windows."
            ),
            (
                "lock",
                "Stays on your Mac",
                "Window positions are never sent anywhere."
            ),
        ] {
            points.addArrangedSubview(point(symbol, heading, line))
        }

        notNow.target = self
        notNow.action = #selector(notNowClicked)
        notNow.keyEquivalent = "\u{1b}"
        primary.target = self
        primary.action = #selector(primaryClicked)
        primary.keyEquivalent = "\r"
        primary.controlSize = .large
        notNow.controlSize = .large
        let buttons = NSStackView(views: [notNow, primary])
        buttons.orientation = .horizontal
        buttons.spacing = 12

        let stack = NSStackView(views: [icon, title, subtitle, points, footnote, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.setCustomSpacing(8, after: icon)
        stack.setCustomSpacing(6, after: title)
        stack.setCustomSpacing(20, after: subtitle)
        stack.setCustomSpacing(20, after: points)
        stack.edgeInsets = NSEdgeInsets(top: 36, left: 32, bottom: 24, right: 32)
        stack.translatesAutoresizingMaskIntoConstraints = false
        w.contentView = stack
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: 420),
            icon.widthAnchor.constraint(equalToConstant: 72),
            icon.heightAnchor.constraint(equalToConstant: 72),
            subtitle.widthAnchor.constraint(equalToConstant: 356),
            footnote.widthAnchor.constraint(equalToConstant: 356),
            points.widthAnchor.constraint(equalToConstant: 340),
        ])
        w.initialFirstResponder = primary
        window = w
    }

    /// One line of the welcome: a symbol, a short bold heading and one line under it.
    private func point(_ symbol: String, _ heading: String, _ line: String) -> NSView {
        let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
        image.symbolConfiguration = .init(pointSize: 18, weight: .regular)
        image.contentTintColor = .controlAccentColor
        let top = NSTextField(labelWithString: heading)
        top.font = .systemFont(ofSize: 13, weight: .semibold)
        let bottom = NSTextField(wrappingLabelWithString: line)
        bottom.font = .systemFont(ofSize: 12)
        bottom.textColor = .secondaryLabelColor
        let text = NSStackView(views: [top, bottom])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let row = NSStackView(views: [image, text])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 12
        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalToConstant: 28),
            bottom.widthAnchor.constraint(equalToConstant: 300),
        ])
        return row
    }

    private func refresh(_ look: Look) {
        self.look = look
        points.isHidden = look != .welcome
        notNow.isHidden = look == .granted
        primary.isHidden = look == .granted
        switch look {
        case .welcome:
            title.stringValue = "Welcome to \(AppIdentity.name)"
            subtitle.stringValue = "Every window back on the right display, every time."
            footnote.stringValue = "Next, macOS will ask you. Turn on \(AppIdentity.name) and you're done. No restart needed."
            primary.title = "Grant Access"
        case .waiting:
            title.stringValue = "Almost there"
            subtitle.stringValue = "In System Settings → Privacy & Security → Accessibility, turn on \(AppIdentity.name)."
            footnote.stringValue = "Not in the list? Add it with the + button from your Applications folder. This window closes by itself."
            primary.title = "Open System Settings"
        case .granted:
            title.stringValue = "You're all set ✓"
            subtitle.stringValue = "\(AppIdentity.name) is in your menu bar, keeping your windows in place."
            footnote.stringValue = ""
            window?.makeFirstResponder(nil)
        }
        footnote.isHidden = footnote.stringValue.isEmpty
        fitToContent()
    }

    /// The looks differ in height; the window follows, keeping its top edge in place.
    private func fitToContent() {
        guard let window, let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content.fittingSize))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true)
    }

    @objc private func primaryClicked() {
        if look == .welcome {
            AX.promptForTrust()
        }
        NSWorkspace.shared.open(Self.settingsURL)
        refresh(.waiting)
    }

    @objc private func notNowClicked() {
        window?.close()
    }

    /// Closing without the permission counts as Not Now: the menu shows the state instead.
    func windowWillClose(_ notification: Notification) {
        if !AX.isTrusted {
            Settings.accessibilityNotNowVersion = AppIdentity.version
            Log.info("Welcome window closed without Accessibility permission")
        }
    }
}
