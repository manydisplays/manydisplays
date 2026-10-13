import ApplicationServices
import CoreGraphics

// Private SkyLight / HIServices symbols. All of them are read-only queries except the
// AX ones, which are widely used by window managers (yabai, AltTab, Amethyst...).
// Functions named *Copy* / *Create* return +1 objects, which matches Swift's owned-return convention.
//
// They are resolved at runtime with dlsym instead of being linked directly, so a macOS
// release that drops one of them degrades the app (nothing is tracked, and the log says why)
// instead of preventing it from launching.

typealias CGSConnectionID = Int32

enum PrivateAPI {
    private typealias CGSMainConnectionIDFn = @convention(c) () -> CGSConnectionID
    private typealias CGSCopyManagedDisplaySpacesFn = @convention(c) (CGSConnectionID) -> Unmanaged<CFArray>?
    private typealias CGSCopySpacesForWindowsFn = @convention(c) (CGSConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias AXUIElementGetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private typealias AXUIElementCreateWithRemoteTokenFn = @convention(c) (CFData) -> Unmanaged<AXUIElement>?

    private static let mainConnectionID = symbol("CGSMainConnectionID", CGSMainConnectionIDFn.self)
    private static let copyManagedDisplaySpaces = symbol("CGSCopyManagedDisplaySpaces", CGSCopyManagedDisplaySpacesFn.self)
    private static let copySpacesForWindows = symbol("CGSCopySpacesForWindows", CGSCopySpacesForWindowsFn.self)
    private static let elementGetWindow = symbol("_AXUIElementGetWindow", AXUIElementGetWindowFn.self)
    private static let createWithRemoteToken = symbol(
        "_AXUIElementCreateWithRemoteToken",
        AXUIElementCreateWithRemoteTokenFn.self
    )

    /// Names of the private symbols this macOS does not provide (empty when everything works).
    static let missing: [String] = {
        var names: [String] = []
        if mainConnectionID == nil {
            names.append("CGSMainConnectionID")
        }
        if copyManagedDisplaySpaces == nil {
            names.append("CGSCopyManagedDisplaySpaces")
        }
        if copySpacesForWindows == nil {
            names.append("CGSCopySpacesForWindows")
        }
        if elementGetWindow == nil {
            names.append("_AXUIElementGetWindow")
        }
        if createWithRemoteToken == nil {
            names.append("_AXUIElementCreateWithRemoteToken")
        }
        return names
    }()

    static var isAvailable: Bool {
        missing.isEmpty
    }

    static func CGSMainConnectionID() -> CGSConnectionID {
        mainConnectionID?() ?? 0
    }

    static func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray? {
        copyManagedDisplaySpaces?(cid)?.takeRetainedValue()
    }

    static func CGSCopySpacesForWindows(_ cid: CGSConnectionID, _ mask: Int32, _ wids: CFArray) -> CFArray? {
        copySpacesForWindows?(cid, mask, wids)?.takeRetainedValue()
    }

    static func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError {
        elementGetWindow?(element, wid) ?? .failure
    }

    static func _AXUIElementCreateWithRemoteToken(_ token: CFData) -> AXUIElement? {
        createWithRemoteToken?(token)?.takeRetainedValue()
    }

    private static func symbol<T>(_ name: String, _: T.Type) -> T? {
        // RTLD_DEFAULT: search every image already loaded (SkyLight and HIServices come with AppKit).
        guard let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(address, to: T.self)
    }
}
