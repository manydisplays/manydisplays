import AppKit

/// "Enter licence" window: a text field, an Activate button and a link to the shop. Main thread.
final class LicenseWindow: NSObject, NSWindowDelegate {
    static let shared = LicenseWindow()

    private var window: NSWindow?
    private let field = NSTextField()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let activate = NSButton(title: "Activate", target: nil, action: nil)

    func show(message: String? = nil) {
        if window == nil {
            build()
        }
        refresh(message: message)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(field)
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

        let title = NSTextField(labelWithString: "Enter your licence key")
        title.font = .boldSystemFont(ofSize: 15)
        let hint = NSTextField(wrappingLabelWithString: "The key was shown after your purchase and sent to your email.")
        hint.textColor = .secondaryLabelColor
        field.placeholderString = "XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX"
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.lineBreakMode = .byTruncatingMiddle
        field.cell?.usesSingleLineMode = true
        field.target = self
        field.action = #selector(activateClicked)
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 12)

        activate.target = self
        activate.action = #selector(activateClicked)
        activate.keyEquivalent = "\r"
        let buy = NSButton(title: "Buy a licence…", target: self, action: #selector(buyClicked))
        buy.bezelStyle = .inline
        buy.isBordered = false
        buy.contentTintColor = .linkColor
        let buttons = NSStackView(views: [buy, NSView(), activate])
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

    private func refresh(message: String?) {
        if let message {
            status.stringValue = message
            return
        }
        switch Licensing.shared.state {
        case .free: status.stringValue = "This build does not need a licence."
        case let .trial(days): status.stringValue = "Trial: \(days) day\(days == 1 ? "" : "s") left."
        case .trialExpired: status.stringValue = "The trial is over. Windows are still tracked, but not restored, until a licence is entered."
        case let .licensed(key):
            let who = key.email.map { "Licensed to \($0)." } ?? "Licensed."
            status.stringValue = who + (key.updatesUntil.map { " Updates until \(Licensing.string($0))." } ?? "")
        case let .updatesExpired(key):
            if key.status == "disabled" {
                status.stringValue = "This licence key was disabled (refunded?). Contact support if that is a mistake."
            } else {
                status.stringValue = "Your licence covers updates until \(key.updatesUntil.map(Licensing.string) ?? "?"); this version is newer. Renew it, or install the last covered version."
            }
        }
    }

    @objc private func activateClicked() {
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        activate.isEnabled = false
        status.textColor = .secondaryLabelColor
        status.stringValue = "Checking the key…"
        Task { @MainActor in
            defer { activate.isEnabled = true }
            do {
                try await Licensing.shared.activate(text)
                field.stringValue = ""
                refresh(message: nil)
                status.textColor = .systemGreen
            } catch LemonSqueezy.Error.rejected(let reason) {
                status.stringValue = reason
                status.textColor = .systemRed
            } catch LemonSqueezy.Error.wrongProduct {
                status.stringValue = "That key belongs to a different product."
                status.textColor = .systemRed
            } catch {
                status.stringValue = "Could not reach the licence server. Check your connection and try again."
                status.textColor = .systemRed
            }
        }
    }

    @objc private func buyClicked() {
        NSWorkspace.shared.open(Licensing.buyURL)
    }

    func windowWillClose(_ notification: Notification) {
        status.textColor = .secondaryLabelColor
    }
}
