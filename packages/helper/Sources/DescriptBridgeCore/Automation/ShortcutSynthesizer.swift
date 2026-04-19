import ApplicationServices
import Foundation

public enum ShortcutError: Error {
    case invalidFormat(String)
    case unsupportedKey(String)
    case eventCreationFailed
}

struct ParsedShortcut {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
}

final class ShortcutSynthesizer {
    func send(_ shortcut: String) throws {
        let parsed = try parse(shortcut)
        let source = CGEventSource(stateID: .combinedSessionState)

        guard
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: parsed.keyCode,
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: parsed.keyCode,
                keyDown: false
            )
        else {
            throw ShortcutError.eventCreationFailed
        }

        keyDown.flags = parsed.flags
        keyUp.flags = parsed.flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func parse(_ shortcut: String) throws -> ParsedShortcut {
        let tokens = shortcut
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        guard !tokens.isEmpty else {
            throw ShortcutError.invalidFormat(shortcut)
        }

        var flags = CGEventFlags()
        var keyCode: CGKeyCode?

        for token in tokens {
            switch token {
            case "cmd", "command":
                flags.insert(.maskCommand)
            case "shift":
                flags.insert(.maskShift)
            case "ctrl", "control":
                flags.insert(.maskControl)
            case "opt", "option", "alt":
                flags.insert(.maskAlternate)
            default:
                keyCode = try mapKeyCode(token)
            }
        }

        guard let keyCode else {
            throw ShortcutError.invalidFormat(shortcut)
        }

        return ParsedShortcut(keyCode: keyCode, flags: flags)
    }

    private func mapKeyCode(_ token: String) throws -> CGKeyCode {
        let numberCodes: [String: CGKeyCode] = [
            "0": 29,
            "1": 18,
            "2": 19,
            "3": 20,
            "4": 21,
            "5": 23,
            "6": 22,
            "7": 26,
            "8": 28,
            "9": 25
        ]

        let letterCodes: [String: CGKeyCode] = [
            "a": 0,
            "b": 11,
            "c": 8,
            "d": 2,
            "e": 14,
            "f": 3,
            "g": 5,
            "h": 4,
            "i": 34,
            "j": 38,
            "k": 40,
            "l": 37,
            "m": 46,
            "n": 45,
            "o": 31,
            "p": 35,
            "q": 12,
            "r": 15,
            "s": 1,
            "t": 17,
            "u": 32,
            "v": 9,
            "w": 13,
            "x": 7,
            "y": 16,
            "z": 6,
            "space": 49,
            "return": 36,
            "enter": 36,
            "period": 47,
            ".": 47,
            "comma": 43,
            ",": 43,
            "slash": 44,
            "/": 44
        ]

        if let code = numberCodes[token] ?? letterCodes[token] {
            return code
        }

        throw ShortcutError.unsupportedKey(token)
    }
}
