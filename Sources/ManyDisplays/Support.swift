import AppKit
import os

enum Log {
    private static let logger = Logger(subsystem: "com.martinacuna.manydisplays", category: "app")
    private static let queue = DispatchQueue(label: "com.martinacuna.manydisplays.log", qos: .background)
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
            let fm = FileManager.default
            if let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue, size > 1_000_000 {
                let old = url.deletingPathExtension().appendingPathExtension("old.log")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: url, to: old)
            }
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
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

    static var paused: Bool {
        get { defaults.bool(forKey: "paused") }
        set { defaults.set(newValue, forKey: "paused") }
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
    func isClose(to other: CGRect, tolerance: CGFloat = 3) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
