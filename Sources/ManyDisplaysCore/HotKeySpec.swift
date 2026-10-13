import Carbon
import Foundation

/// A global shortcut written as text, e.g. "ctrl+alt+cmd+r". Users change the defaults with
/// `defaults write <bundle id> restoreHotKey -string "ctrl+shift+r"`.
struct HotKeySpec: Equatable {
    let keyCode: Int
    let modifiers: Int
    /// The same shortcut as an NSMenuItem key equivalent (`key`) and modifier mask.
    let key: String

    static let modifierNames: [String: Int] = [
        "ctrl": controlKey, "control": controlKey,
        "alt": optionKey, "opt": optionKey, "option": optionKey,
        "cmd": cmdKey, "command": cmdKey,
        "shift": shiftKey,
    ]

    private static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
        "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
        "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
        "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
        "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6,
        "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
    ]

    /// nil when the text is not a modifier combination plus one key, or has no modifier at all
    /// (a global shortcut without modifiers would swallow normal typing).
    init?(_ text: String) {
        let parts = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.last, let code = Self.keyCodes[last] else { return nil }
        var mods = 0
        for part in parts.dropLast() {
            guard let flag = Self.modifierNames[part] else { return nil }
            mods |= flag
        }
        guard mods != 0 else { return nil }
        keyCode = code
        modifiers = mods
        key = last
    }
}
