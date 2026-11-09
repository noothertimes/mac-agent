import CoreGraphics

public enum KeyComboError: Error, Equatable, CustomStringConvertible {
    case empty
    case unknownKey(String)
    case unknownModifier(String)

    public var description: String {
        switch self {
        case .empty: return "Empty key combo"
        case .unknownKey(let key): return "Unknown key: \(key)"
        case .unknownModifier(let mod): return "Unknown modifier: \(mod)"
        }
    }
}

/// A key press like "cmd+shift+t" or "return", as a virtual key code plus modifier flags.
public struct KeyCombo: Equatable {
    public let keyCode: CGKeyCode
    public let flags: CGEventFlags

    public static func parse(_ text: String) throws -> KeyCombo {
        let parts = text.lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let keyName = parts.last else { throw KeyComboError.empty }
        guard let code = keyCodes[keyName] else { throw KeyComboError.unknownKey(keyName) }

        var flags: CGEventFlags = []
        for name in parts.dropLast() {
            guard let flag = modifiers[name] else { throw KeyComboError.unknownModifier(name) }
            flags.insert(flag)
        }
        return KeyCombo(keyCode: code, flags: flags)
    }

    static let modifiers: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand,
        "shift": .maskShift,
        "alt": .maskAlternate, "opt": .maskAlternate, "option": .maskAlternate,
        "ctrl": .maskControl, "control": .maskControl,
        "fn": .maskSecondaryFn,
    ]

    // US ANSI layout virtual key codes.
    static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "`": 50,
        "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51,
        "escape": 53, "esc": 53, "forwarddelete": 117,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]
}
