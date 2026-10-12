import AppKit

/// Blurred veil with a spinner over every display while windows are being put back,
/// so the shuffling is not visible. Main thread only.
final class RestoreOverlay: NSObject {
    static let shared = RestoreOverlay()

    /// After this long a "Cerrar" link shows up, in case a slow app keeps the veil on screen.
    private static let closeDelay: TimeInterval = 4
    /// Hard limit: the veil never stays longer than this.
    private static let maxDuration: TimeInterval = 15

    private var windows: [NSWindow] = []
    private var closeButtons: [NSButton] = []
    private var hideWork: DispatchWorkItem?

    func show() {
        // Only with external monitors: on the MacBook alone the app never restores anything.
        guard windows.isEmpty, Displays.hasExternal(Displays.current()) else { return }
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
            window.contentView = makeContent(size: screen.frame.size)
            window.setFrame(screen.frame, display: false)
            window.orderFrontRegardless()
            windows.append(window)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            windows.forEach { $0.animator().alphaValue = 0.75 } // soft veil, the desktop stays recognizable
        }
        // Never leave the screens covered if something goes wrong.
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.maxDuration, execute: work)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeDelay) { [weak self] in
            guard let self else { return }
            for button in self.closeButtons {
                button.alphaValue = 0
                button.isHidden = false
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4
                self.closeButtons.forEach { $0.animator().alphaValue = 1 }
            }
        }
    }

    /// Only hides the veil; the restore keeps going in the background.
    @objc private func closeClicked() {
        Log.info("Difuminado cerrado por el usuario")
        hide()
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        guard !windows.isEmpty else { return }
        let closing = windows
        windows.removeAll()
        closeButtons.removeAll()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            closing.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            closing.forEach { $0.orderOut(nil) }
        })
    }

    private func makeContent(size: NSSize) -> NSView {
        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]

        // Small HUD pill in the middle: spinner + short text.
        let pill = NSVisualEffectView()
        pill.material = .hudWindow
        pill.blendingMode = .withinWindow
        pill.state = .active
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 18
        pill.layer?.masksToBounds = true
        pill.translatesAutoresizingMaskIntoConstraints = false

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)

        let label = NSTextField(labelWithString: "Ordenando ventanas")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [spinner, label])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 9, left: 14, bottom: 9, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(stack)
        blur.addSubview(pill)

        let close = NSButton(title: "", target: self, action: #selector(closeClicked))
        close.isBordered = false
        close.attributedTitle = NSAttributedString(string: "Cerrar", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
        close.isHidden = true
        close.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(close)
        closeButtons.append(close)

        NSLayoutConstraint.activate([
            close.centerXAnchor.constraint(equalTo: blur.centerXAnchor),
            close.topAnchor.constraint(equalTo: pill.bottomAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: pill.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: pill.trailingAnchor),
            stack.topAnchor.constraint(equalTo: pill.topAnchor),
            stack.bottomAnchor.constraint(equalTo: pill.bottomAnchor),
            pill.centerXAnchor.constraint(equalTo: blur.centerXAnchor),
            pill.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
        ])
        return blur
    }
}
