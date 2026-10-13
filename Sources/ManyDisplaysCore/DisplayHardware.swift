import CoreGraphics
import Foundation
import IOKit

/// Physical port of each external display (Apple Silicon). Lets us tell apart identical
/// monitors that report the same EDID serial: they still sit on different ports.
enum DisplayPorts {
    private struct Framebuffer {
        let port: Int
        let serial: UInt32
        let product: UInt32
    }

    /// CGDirectDisplayID -> hardware PortID. External framebuffers are named "dispextN" and
    /// CGDisplayUnitNumber is N + 1 (the built-in panel is unit 0). The mapping is only used
    /// when the framebuffer's EDID serial/product match the display, so a wrong guess is ignored.
    static func portIDs(for ids: [CGDirectDisplayID]) -> [CGDirectDisplayID: Int] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMobileFramebufferShim"), &iterator) ==
            KERN_SUCCESS else {
            return [:]
        }
        defer { IOObjectRelease(iterator) }

        var framebuffers: [Int: Framebuffer] = [:]
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let name = property(service, "IONameMatched") as? String, name.hasPrefix("dispext"),
                  let index = Int(name.dropFirst("dispext".count).prefix { $0.isNumber }),
                  let attributes = property(service, "DisplayAttributes") as? [String: Any],
                  let port = (attributes["PortID"] as? NSNumber)?.intValue
            else { continue }
            let product = attributes["ProductAttributes"] as? [String: Any]
            framebuffers[index] = Framebuffer(
                port: port,
                serial: (product?["SerialNumber"] as? NSNumber)?.uint32Value ?? 0,
                product: (product?["ProductID"] as? NSNumber)?.uint32Value ?? 0
            )
        }

        var result: [CGDirectDisplayID: Int] = [:]
        for id in ids where CGDisplayIsBuiltin(id) == 0 {
            let unit = Int(CGDisplayUnitNumber(id))
            guard unit >= 1, let fb = framebuffers[unit - 1],
                  fb.serial == CGDisplaySerialNumber(id), fb.product == CGDisplayModelNumber(id) else { continue }
            result[id] = fb.port
        }
        return result
    }

    private static func property(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

/// Rotation and HDR through the private MonitorPanel framework (what System Settings uses).
/// Reading costs ~25 ms, so callers cache the result.
enum DisplayPanel {
    private static let loaded: Bool = dlopen("/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel", RTLD_NOW) !=
        nil

    private static func displays() -> [CGDirectDisplayID: NSObject] {
        guard loaded, let managerClass = NSClassFromString("MPDisplayMgr") as? NSObject.Type else { return [:] }
        let manager = managerClass.init()
        guard let list = manager.value(forKey: "displays") as? [NSObject] else { return [:] }
        var result: [CGDirectDisplayID: NSObject] = [:]
        for display in list {
            if let id = (display.value(forKey: "displayID") as? NSNumber)?.uint32Value {
                result[id] = display
            }
        }
        return result
    }

    /// HDR preference for displays that support HDR (others are omitted).
    static func hdrStates() -> [CGDirectDisplayID: Bool] {
        var result: [CGDirectDisplayID: Bool] = [:]
        for (id, display) in displays() where (display.value(forKey: "hasHDRModes") as? Bool) == true {
            result[id] = display.value(forKey: "preferHDRModes") as? Bool
        }
        return result
    }

    static func setHDR(_ on: Bool, for id: CGDirectDisplayID) -> Bool {
        guard let display = displays()[id], (display.value(forKey: "hasHDRModes") as? Bool) == true,
              display.responds(to: NSSelectorFromString("setPreferHDRModes:")) else { return false }
        display.setValue(on, forKey: "preferHDRModes")
        return true
    }

    static func setRotation(_ degrees: Int, for id: CGDirectDisplayID) -> Bool {
        guard let display = displays()[id], (display.value(forKey: "canChangeOrientation") as? Bool) == true,
              display.responds(to: NSSelectorFromString("setOrientation:")) else { return false }
        display.setValue(degrees, forKey: "orientation")
        return true
    }
}
