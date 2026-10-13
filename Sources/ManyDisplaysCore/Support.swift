import AppKit
import os

/// Identifiers shared by the app, its log, its queues and its command-line commands.
enum AppIdentity {
    static let bundleID = "com.manydisplays.ManyDisplays"
    static let name = "Many Displays"
    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(short) (\($0))" } ?? short
    }
}

enum Log {
    private static let logger = Logger(subsystem: AppIdentity.bundleID, category: "app")
    private static let queue = DispatchQueue(label: AppIdentity.bundleID + ".log", qos: .background)
    /// Kept open between lines; reopened after rotation.
    private static var handle: FileHandle?
    private static var linesSinceSizeCheck = 0
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ManyDisplays.log")
    }()

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        queue.async {
            rotateIfNeeded()
            guard let data = line.data(using: .utf8) else { return }
            if handle == nil {
                if !FileManager.default.fileExists(atPath: url.path) {
                    try? Data().write(to: url)
                }
                handle = try? FileHandle(forWritingTo: url)
                handle?.seekToEndOfFile()
            }
            handle?.write(data)
        }
    }

    /// Keeps the file around 1 MB: the previous log is kept as ManyDisplays.old.log.
    private static func rotateIfNeeded() {
        linesSinceSizeCheck += 1
        guard linesSinceSizeCheck >= 200 || handle == nil else { return }
        linesSinceSizeCheck = 0
        let fm = FileManager.default
        guard let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue,
              size > 1_000_000 else { return }
        try? handle?.close()
        handle = nil
        let old = url.deletingPathExtension().appendingPathExtension("old.log")
        try? fm.removeItem(at: old)
        try? fm.moveItem(at: url, to: old)
    }
}

enum Settings {
    private static let defaults = UserDefaults.standard

    static var fixArrangement: Bool {
        get { defaults.object(forKey: "fixArrangement") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "fixArrangement") }
    }

    static var blurWhileRestoring: Bool {
        get { defaults.object(forKey: "blurWhileRestoring") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "blurWhileRestoring") }
    }

    /// Smoothed time the blur overlay stays up (visible windows only), for its countdown.
    static var overlayDuration: TimeInterval {
        get { defaults.object(forKey: "overlayDuration") as? Double ?? 2.0 }
        set { defaults.set(newValue, forKey: "overlayDuration") }
    }

    static var paused: Bool {
        get { defaults.bool(forKey: "paused") }
        set { defaults.set(newValue, forKey: "paused") }
    }

    /// Global shortcuts, as text ("ctrl+alt+cmd+r"). Set to an empty string to disable one.
    static var restoreHotKey: HotKeySpec? {
        hotKey("restoreHotKey", default: "ctrl+alt+cmd+r")
    }

    static var saveHotKey: HotKeySpec? {
        hotKey("saveHotKey", default: "ctrl+alt+cmd+s")
    }

    private static func hotKey(_ key: String, default fallback: String) -> HotKeySpec? {
        guard let text = defaults.string(forKey: key) else { return HotKeySpec(fallback) }
        if text.isEmpty {
            return nil
        }
        guard let spec = HotKeySpec(text) else {
            Log.info("Ignoring invalid shortcut for \(key): \"\(text)\" (expected e.g. ctrl+alt+cmd+r)")
            return HotKeySpec(fallback)
        }
        return spec
    }
}

/// When the user last clicked, dragged or used a keyboard shortcut. Window changes that follow
/// within a moment are the user's; changes without recent input come from macOS or the app.
enum UserInput {
    private static let lock = NSLock()
    private static var last = Date.distantPast
    private static var monitor: Any?

    /// Needs Accessibility permission; safe to call again once it is granted.
    static func startMonitoring() {
        guard monitor == nil, AXIsProcessTrusted() else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDown, .leftMouseDragged, .rightMouseDown, .otherMouseDown, .keyDown,
        ]) { event in
            if event.type == .keyDown,
               event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                return
            }
            mark()
        }
    }

    static func mark() {
        lock.lock()
        last = Date()
        lock.unlock()
    }

    static func happened(within seconds: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return Date().timeIntervalSince(last) < seconds
    }
}

enum Boot {
    /// Changes on every reboot. Window IDs are only meaningful inside one boot session.
    static let session: String = {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &tv, &size, nil, 0)
        return String(tv.tv_sec)
    }()
}

/// NSScreen names must be read on the main thread; the engine reads this cache from its own queue.
enum DisplayNames {
    private static let lock = NSLock()
    private static var names: [CGDirectDisplayID: String] = [:]

    static func refresh() {
        var fresh: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                fresh[number.uint32Value] = screen.localizedName
            }
        }
        lock.lock()
        names = fresh
        lock.unlock()
    }

    static func name(for id: CGDirectDisplayID) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return names[id]
    }
}

extension CGRect {
    /// Close enough to count as restored: exact position, a little slack on size for apps that
    /// snap their size to a grid (terminals, editors).
    func matches(_ target: CGRect) -> Bool {
        abs(minX - target.minX) <= 4 && abs(minY - target.minY) <= 4
            && abs(width - target.width) <= 20 && abs(height - target.height) <= 20
    }

    func isClose(to other: CGRect, tolerance: CGFloat = 3) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
