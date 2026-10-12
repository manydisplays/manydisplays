import CoreGraphics
import Foundation

struct WindowRecord: Codable, Equatable {
    var windowID: CGWindowID
    var pid: pid_t
    var bundleID: String?
    var appName: String
    var title: String?
    /// Key of the physical display the window belongs to (see Displays.current()).
    var displayKey: String
    /// Frame relative to that display's top-left corner, so it survives arrangement changes.
    var relFrame: CGRect
    var spaceID: UInt64?
    var spaceIndex: Int?
    var onAllSpaces: Bool
    var fullscreen: Bool
}

/// The last known window layout for one combination of displays.
struct Layout: Codable, Equatable {
    var profileID: String
    var displays: [DisplayInfo] = []
    /// Keyed by String(windowID).
    var windows: [String: WindowRecord] = [:]
    var bootSession: String = Boot.session
    var updatedAt = Date()

    init(profileID: String) { self.profileID = profileID }
}

/// Persists every layout in ~/Library/Application Support/ManyDisplays/layouts.json.
/// Only touched from the engine queue. Writes happen only when something actually changed.
final class LayoutStore {
    private struct FileFormat: Codable {
        var version = 1
        var layouts: [String: Layout]
    }

    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ManyDisplays", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let url = LayoutStore.directory.appendingPathComponent("layouts.json")
    private(set) var layouts: [String: Layout] = [:]
    private(set) var isDirty = false

    init() {
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            layouts = try decoder.decode(FileFormat.self, from: data).layouts
        } catch {
            Log.info("No se pudo leer layouts.json (\(error)); se guarda una copia y se empieza de cero")
            try? FileManager.default.copyItem(at: url, to: url.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))"))
        }
    }

    func layout(_ profileID: String) -> Layout? { layouts[profileID] }

    /// Returns true if the layout changed.
    @discardableResult
    func put(_ layout: Layout) -> Bool {
        if let old = layouts[layout.profileID], old.windows == layout.windows, old.displays == layout.displays,
           old.bootSession == layout.bootSession {
            return false
        }
        var updated = layout
        updated.updatedAt = Date()
        layouts[layout.profileID] = updated
        isDirty = true
        return true
    }

    func remove(_ profileID: String) {
        guard layouts.removeValue(forKey: profileID) != nil else { return }
        isDirty = true
    }

    func flush() {
        guard isDirty else { return }
        do {
            let data = try encoder.encode(FileFormat(layouts: layouts))
            try data.write(to: url, options: .atomic)
            isDirty = false
        } catch {
            Log.info("Error guardando layouts: \(error)")
        }
    }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
