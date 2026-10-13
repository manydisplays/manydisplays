import Foundation

/// Every timing and threshold in one place. The values were tuned on real hardware (two
/// identical 4K monitors, ten desktops); the comments say what each one protects against.
enum Tuning {

    // MARK: Saving

    /// Debounce after a window event before the layout is captured.
    static let snapshotDebounce: TimeInterval = 1.5
    /// Debounce after switching desktop (the swipe animation is still running).
    static let spaceChangeDebounce: TimeInterval = 1.0
    /// Fallback capture for changes that produce no Accessibility notification.
    static let heartbeatInterval: TimeInterval = 20
    /// Layout changes are written to disk at most this often.
    static let flushDelay: TimeInterval = 3
    /// A frame change on screen counts as the user's if they touched the mouse/keyboard this recently.
    static let userInputWindow: TimeInterval = 5
    /// How long a window stays "moved by the user" (protects it from the drift guard).
    static let userMoveMemory: TimeInterval = 30

    // MARK: Settling

    /// Displays must be stable for this long after a reconfiguration before anything runs.
    static let displaySettle: TimeInterval = 2.5
    /// Wait after wake / display wake (monitors reconnect slowly).
    static let wakeSettle: TimeInterval = 3.0
    /// If no wake/unlock notification ever arrives, leave the frozen state after this long.
    static let watchdog: TimeInterval = 30
    /// Pause between display fixes (rotation, resolution, HDR): each one reconfigures the displays.
    static let displayFixSettle: TimeInterval = 3.0

    // MARK: Restoring

    /// Delays of the quick passes over visible windows (macOS keeps nudging them for a while).
    static let restorePassDelays: [TimeInterval] = [0, 1.5, 4.0]
    /// Windows that could not be restored keep their saved position protected this long.
    static let pendingExpiry: TimeInterval = 30 * 60
    /// Visits to a window's desktop before giving up on an app that refuses to move it.
    static let pendingMaxAttempts = 3
    /// Wait after a retry on the window's desktop before checking whether it stuck.
    static let pendingVerifyDelay: TimeInterval = 0.7
    /// After a restore, drift that nobody asked for is undone instead of saved for this long.
    static let guardDuration: TimeInterval = 180
    /// Times a drifted window is put back before accepting the app's choice.
    static let guardMaxAttempts = 3
    /// Windows restored on a hidden desktop stay guarded until it is shown, at most this long...
    static let offSpaceWatchMax: TimeInterval = 2 * 3600
    /// ...and for this long after it becomes visible.
    static let offSpaceWatchAfterVisible: TimeInterval = 20
    /// After a restore, saved changes are logged (to see who moves windows) for this long.
    static let postRestoreDiagnostics: TimeInterval = 600
    /// Strips narrower/shorter than this (Chrome tab-drag helpers...) are not real windows.
    static let minimumWindowSide: CGFloat = 100

    // MARK: Accessibility

    /// Time budget of the deep element scan per app (finds windows on other desktops).
    static let deepScanBudget: TimeInterval = 1.0
    /// Element ids probed per app in a deep scan (Chrome reaches ~20k after days open).
    static let deepScanElementLimit: UInt64 = 60000
    /// Cached AX elements / titles / user-move marks are dropped past these sizes.
    static let elementCacheLimit = 600
    static let titleCacheLimit = 3000
    static let userMoveCacheLimit = 500
}
