import AppKit

/// Blurred veil over every display while windows are being put back, so the shuffling is not
/// visible. Shows a countdown based on how long restores usually take on this Mac; if it runs
/// past the estimate, a "Close" link appears. Main thread only.
final class RestoreOverlay: NSObject {
    static let shared = RestoreOverlay()

    /// Hard limit: the veil never stays longer than this.
    private static let maxDuration: TimeInterval = 10

    private struct Screen {
        let window: NSWindow
        let title: NSTextField
        let number: NSTextField
        let close: NSButton
    }

    private var screens: [Screen] = []
    private var hideWork: DispatchWorkItem?
    private var timer: Timer?
    private var shownAt = Date()
    private var estimate: TimeInterval = 3
    private var expired: Bool { Date().timeIntervalSince(shownAt) >= estimate }

    func show(estimate: TimeInterval = 3) {
        // Only with external monitors: on the MacBook alone the app never restores anything.
        guard screens.isEmpty, Displays.hasExternal(Displays.current()) else { return }
        self.estimate = min(max(estimate, 1.5), 12)
        shownAt = Date()
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = false // swallow clicks while things move
            window.isReleasedWhenClosed = false
            window.alphaValue = 0
            screens.append(makeContent(in: window, size: screen.frame.size))
            window.setFrame(screen.frame, display: false)
            window.orderFrontRegardless()
        }
        tick()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            screens.forEach { $0.window.animator().alphaValue = 0.8 } // soft veil, the desktop stays recognizable
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }

        // Never leave the screens covered if something goes wrong.
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.maxDuration, execute: work)
    }

    private func tick() {
        let remaining = estimate - Date().timeIntervalSince(shownAt)
        if remaining > 0 {
            let text = "\(Int(remaining.rounded(.up)))"
            for s in screens where s.number.stringValue != text { s.number.stringValue = text }
        } else {
            // Taking longer than usual: let the user get their screen back.
            for s in screens where s.close.isHidden {
                s.number.stringValue = "…"
                s.title.stringValue = "Almost done · click to close"
                s.close.alphaValue = 0
                s.close.isHidden = false
                NSAnimationContext.runAnimationGroup { $0.duration = 0.3; s.close.animator().alphaValue = 1 }
            }
        }
    }

    /// Restore finished: show a check mark briefly, then fade out.
    func finish() {
        guard !screens.isEmpty else { return }
        timer?.invalidate()
        timer = nil
        for s in screens {
            s.number.stringValue = "✓"
            s.title.stringValue = "Done"
            s.close.isHidden = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.hide() }
    }

    /// Only hides the veil; the restore keeps going in the background.
    @objc private func closeClicked() {
        Log.info("Blur overlay closed by user")
        hide()
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        timer?.invalidate()
        timer = nil
        guard !screens.isEmpty else { return }
        let closing = screens.map(\.window)
        screens.removeAll()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            closing.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            closing.forEach { $0.orderOut(nil) }
        })
    }

    private func makeContent(in window: NSWindow, size: NSSize) -> Screen {
        let blur = VeilView(frame: NSRect(origin: .zero, size: size))
        // Once the countdown is over, a click anywhere gives the screen back.
        blur.onClick = { [weak self] in
            guard let self, self.expired else { return }
            Log.info("Blur overlay closed by user")
            self.hide()
        }
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        window.contentView = blur

        // HUD card in the middle: short title and a big countdown.
        let card = NSVisualEffectView()
        card.material = .hudWindow
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 22
        card.layer?.masksToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Arranging windows")
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.textColor = .secondaryLabelColor
        title.alignment = .center

        let number = NSTextField(labelWithString: "")
        number.font = .monospacedDigitSystemFont(ofSize: 54, weight: .light)
        number.textColor = .labelColor
        number.alignment = .center

        let stack = NSStackView(views: [title, number])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 28, bottom: 12, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        blur.addSubview(card)

        let close = NSButton(title: "", target: self, action: #selector(closeClicked))
        close.isBordered = false
        close.attributedTitle = NSAttributedString(string: "Close", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
        close.isHidden = true
        close.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(close)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            card.widthAnchor.constraint(greaterThanOrEqualToConstant: 170),
            card.centerXAnchor.constraint(equalTo: blur.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
            close.centerXAnchor.constraint(equalTo: blur.centerXAnchor),
            close.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 12),
        ])
        return Screen(window: window, title: title, number: number, close: close)
    }
}

/// The blurred veil; swallows clicks (so nothing gets moved mid-restore) and reports them.
private final class VeilView: NSVisualEffectView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
