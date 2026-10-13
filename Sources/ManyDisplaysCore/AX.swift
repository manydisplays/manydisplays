import AppKit
import ApplicationServices

enum AX {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func promptForTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func application(_ pid: pid_t, timeout: Float = 0.5) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        return app
    }

    static func windowID(_ element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return PrivateAPI._AXUIElementGetWindow(element, &id) == .success && id != 0 ? id : nil
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    static func title(_ element: AXUIElement) -> String? {
        (attribute(element, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The frame the app reports. Unlike CGWindowList bounds, it is not affected by Mission
    /// Control or Space-switch animations, which temporarily transform windows on screen.
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = attribute(element, kAXPositionAttribute), let s = attribute(element, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    static func isMinimized(_ element: AXUIElement) -> Bool {
        (attribute(element, kAXMinimizedAttribute) as? Bool) ?? false
    }

    /// Windows that the app reports through the standard attribute (usually only the current space).
    static func standardWindows(_ app: AXUIElement) -> [AXUIElement] {
        attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
    }

    /// Finds AX elements for the wanted window ids. With `deep`, also windows that live in
    /// other spaces (which kAXWindowsAttribute hides): it builds remote element tokens
    /// directly, the technique AltTab uses. Element ids grow over an app's lifetime (Chrome
    /// reaches ~20k after days open), so the scan is wide but stops as soon as all are found.
    static func elements(
        pid: pid_t,
        wanted: Set<CGWindowID>,
        deep: Bool,
        budget: TimeInterval = Tuning.deepScanBudget
    ) -> [CGWindowID: AXUIElement] {
        let app = application(pid)
        var found: [CGWindowID: AXUIElement] = [:]
        for element in standardWindows(app) {
            if let id = windowID(element), wanted.contains(id) {
                found[id] = element
            }
        }
        guard deep, found.count < wanted.count else { return found }

        var token = Data(count: 20)
        token.replaceSubrange(0 ..< 4, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(4 ..< 8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
        token.replaceSubrange(8 ..< 12, with: withUnsafeBytes(of: Int32(0x636F_636F)) { Data($0) })
        // Each probe can wait up to the element's messaging timeout when the app is busy, so the
        // budget is checked on every iteration (an unresponsive app must not stall the engine).
        let deadline = Date().addingTimeInterval(budget)
        for elementID: UInt64 in 0 ..< Tuning.deepScanElementLimit {
            if Date() > deadline {
                break
            }
            token.replaceSubrange(12 ..< 20, with: withUnsafeBytes(of: elementID) { Data($0) })
            guard let element = PrivateAPI._AXUIElementCreateWithRemoteToken(token as CFData) else { continue }
            AXUIElementSetMessagingTimeout(element, 0.1)
            // Child elements also report their window id, so check the role.
            guard let id = windowID(element), wanted.contains(id), found[id] == nil,
                  (attribute(element, kAXRoleAttribute) as? String) == kAXWindowRole else { continue }
            found[id] = element
            if found.count == wanted.count {
                break
            }
        }
        return found
    }

    /// Moves and resizes a window. Position is set twice because some apps clamp the size
    /// to the display they are on before the move.
    @discardableResult
    static func setFrame(_ element: AXUIElement, app: AXUIElement, to frame: CGRect) -> Bool {
        // AXEnhancedUserInterface (enabled by VoiceOver-like tools) makes Chrome/Electron
        // animate every change; turn it off while moving, as Rectangle does.
        let enhanced = (attribute(app, "AXEnhancedUserInterface") as? Bool) ?? false
        if enhanced {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
        }
        defer {
            if enhanced {
                AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            }
        }

        var origin = frame.origin
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &origin), let dimensions = AXValueCreate(.cgSize, &size) else {
            return false
        }
        let first = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
        let sized = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, dimensions)
        let second = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
        lastError = (first == .success || second == .success) && sized == .success ? nil
            : "position=\(first.rawValue)/\(second.rawValue) size=\(sized.rawValue)"
        return first == .success || second == .success
    }

    /// AXError codes of the last setFrame that did not fully succeed (for the log), on the engine queue.
    nonisolated(unsafe) static var lastError: String?
}
