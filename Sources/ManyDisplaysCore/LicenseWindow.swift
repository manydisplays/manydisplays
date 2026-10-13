import AppKit

/// The licence window. Two looks: a field with an Activate button while the app is unlicensed,
/// and a green "Activated" summary with Remove Licence / Done once a key is in. Main thread.
final class LicenseWindow: NSObject, NSWindowDelegate {
    static let shared = LicenseWindow()

    private var window: NSWindow?
    private let title = NSTextField(labelWithString: "")
    private let hint = NSTextField(wrappingLabelWithString: "")
    private let field = NSTextField()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let buy = NSButton(title: "Buy a licence…", target: nil, action: nil)
    private let remove = NSButton(title: "Remove Licence…", target: nil, action: nil)
    private let activate = NSButton(title: "Activate", target: nil, action: nil)
    private let done = NSButton(title: "Done", target: nil, action: nil)

    func show(message: String? = nil) {
        if window == nil {
            build()
        }
        refresh(message: message)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        if !field.isHidden {
            window?.makeFirstResponder(field)
        }
    }

    private func build() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 230),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "\(AppIdentity.name) Licence"
        w.isReleasedWhenClosed = false
        w.delegate = self

        title.font = .boldSystemFont(ofSize: 15)
        hint.textColor = .secondaryLabelColor
        field.placeholderString = "MD1.…"
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.lineBreakMode = .byTruncatingMiddle
        field.cell?.usesSingleLineMode = true
        field.target = self
        field.action = #selector(activateClicked)
        status.font = .systemFont(ofSize: 12)

        activate.target = self
        activate.action = #selector(activateClicked)
        activate.keyEquivalent = "\r"
        done.target = self
        done.action = #selector(doneClicked)
        done.keyEquivalent = "\r"
        for link in [buy, remove] {
            link.target = self
            link.bezelStyle = .inline
            link.isBordered = false
            link.contentTintColor = .linkColor
        }
        buy.action = #selector(buyClicked)
        remove.action = #selector(removeClicked)
        let buttons = NSStackView(views: [buy, remove, NSView(), activate, done])
        buttons.orientation = .horizontal

        let stack = NSStackView(views: [title, hint, field, status, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        w.contentView = stack
        NSLayoutConstraint.activate([
            field.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            hint.widthAnchor.constraint(equalTo: field.widthAnchor),
            status.widthAnchor.constraint(equalTo: field.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: field.widthAnchor),
        ])
        window = w
    }

    /// Lays the window out for the current licence state; `message` overrides the status line.
    private func refresh(message: String?) {
        let state = Licensing.shared.state
        let licensed = if case .licensed = state {
            true
        } else {
            false
        }
        field.isHidden = licensed
        activate.isHidden = licensed
        buy.isHidden = licensed
        remove.isHidden = !licensed
        done.isHidden = !licensed
        status.textColor = .secondaryLabelColor

        switch state {
        case let .licensed(key):
            title.stringValue = "✓ Activated"
            hint.stringValue = "Licensed to \(key.email). Covers every version released until \(Licensing.string(key.updatesUntil)); those versions keep working forever."
            status.stringValue = "The key is stored on this Mac. You can enter the same key on your other Macs."
        case .free:
            title.stringValue = "Enter your licence key"
            hint.stringValue = "This build does not need a licence."
            status.stringValue = ""
        case let .trial(days):
            title.stringValue = "Enter your licence key"
            hint.stringValue = "The key was shown after your purchase and sent to your email. It starts with MD1."
            status.stringValue = "Trial: \(days) day\(days == 1 ? "" : "s") left."
        case .trialExpired:
            title.stringValue = "Enter your licence key"
            hint.stringValue = "The key was shown after your purchase and sent to your email. It starts with MD1."
            status.stringValue = "The trial is over. Window positions are still remembered, but not restored, until a licence is entered."
        case let .updatesExpired(key):
            title.stringValue = "This version is not covered"
            hint.stringValue = "Your licence (\(key.email)) covers updates until \(Licensing.string(key.updatesUntil)) and this version is newer. Renew it, enter a newer key, or install the last covered version."
            status.stringValue = ""
            buy.title = "Renew the licence…"
        }
        if let message {
            status.stringValue = message
        }
    }

    @objc private func activateClicked() {
        do {
            try Licensing.shared.activate(field.stringValue)
            field.stringValue = ""
            refresh(message: nil)
            title.textColor = .systemGreen
        } catch LicenseKey.Error.badSignature {
            refresh(message: "That key is not valid for this app. Check that it was copied completely.")
            status.textColor = .systemRed
        } catch {
            refresh(message: "That does not look like a licence key (it starts with MD1.).")
            status.textColor = .systemRed
        }
    }

    @objc private func removeClicked() {
        let alert = NSAlert()
        alert.messageText = "Remove the licence from this Mac?"
        alert.informativeText = "The app goes back to the state before the key was entered. You can enter the key again at any time."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Licensing.shared.deactivate()
        title.textColor = .labelColor
        refresh(message: nil)
        window?.makeFirstResponder(field)
    }

    @objc private func doneClicked() {
        window?.close()
    }

    @objc private func buyClicked() {
        NSWorkspace.shared.open(Licensing.buyURL)
    }

    func windowWillClose(_ notification: Notification) {
        title.textColor = .labelColor
    }
}
