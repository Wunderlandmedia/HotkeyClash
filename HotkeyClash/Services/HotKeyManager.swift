import AppKit
import Carbon
import os

private let logger = Logger(subsystem: "com.hotkeyclash.app", category: "HotKeyManager")

@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    /// Invoked from the Carbon hot-key callback, which Carbon delivers on the main
    /// thread. Kept main-actor isolated; do not invoke it from any other context.
    private var onTrigger: (() -> Void)?

    private init() {}

    func register(keyCode: UInt32, modifiers: UInt32, onTrigger: @escaping () -> Void) {
        unregister()
        self.onTrigger = onTrigger

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        // Carbon delivers kEventHotKeyPressed on the main thread, so assuming
        // main-actor isolation to reach the stored trigger is safe here.
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { (_, _, _) -> OSStatus in
            MainActor.assumeIsolated {
                HotKeyManager.shared.onTrigger?()
            }
            return noErr
        }, 1, &eventType, nil, &handlerRef)
        if installStatus != noErr {
            logger.error("Failed to install hot-key event handler: \(installStatus)")
        }

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x484B_434C) // "HKCL"
        hotKeyID.id = 1

        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status == noErr {
            let display = ShortcutFormatter.displayString(keyCode: keyCode, carbonModifiers: modifiers)
            logger.info("Global hotkey registered: \(display)")
        } else {
            logger.error("Failed to register hotkey: \(status)")
        }
    }

    func reregister(keyCode: UInt32, modifiers: UInt32) {
        guard let trigger = onTrigger else { return }
        register(keyCode: keyCode, modifiers: modifiers, onTrigger: trigger)
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = handlerRef {
            RemoveEventHandler(ref)
            handlerRef = nil
        }
    }
}

enum ShortcutFormatter {
    static func displayString(keyCode: UInt32, carbonModifiers: UInt32) -> String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("\u{2303}") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("\u{2325}") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("\u{21E7}") }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("\u{2318}") }
        parts.append(keyName(for: keyCode))
        return parts.joined()
    }

    /// A plain-text, spelled-out form of the combo for searching, e.g.
    /// "command cmd shift c". Includes modifier synonyms so a typed query like
    /// "shift", "cmd", or "alt" matches a combo that only displays as glyphs.
    static func searchableString(keyCode: UInt32, carbonModifiers: UInt32) -> String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("control ctrl") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("option opt alt") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("shift") }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("command cmd") }
        parts.append(searchableKeyName(for: keyCode))
        return parts.joined(separator: " ")
    }

    /// Spelled-out key name for searching. Keys shown as glyphs (return, space,
    /// arrows, etc.) get word forms; letters and numbers fall back to `keyName`.
    static func searchableKeyName(for keyCode: UInt32) -> String {
        switch keyCode {
        case 0x24: "return enter"
        case 0x30: "tab"
        case 0x31: "space"
        case 0x33: "delete backspace"
        case 0x35: "escape esc"
        case 0x7B: "left arrow"
        case 0x7C: "right arrow"
        case 0x7D: "down arrow"
        case 0x7E: "up arrow"
        default: keyName(for: keyCode).lowercased()
        }
    }

    static func keyName(for keyCode: UInt32) -> String {
        switch keyCode {
        case 0x00: "A"
        case 0x01: "S"
        case 0x02: "D"
        case 0x03: "F"
        case 0x04: "H"
        case 0x05: "G"
        case 0x06: "Z"
        case 0x07: "X"
        case 0x08: "C"
        case 0x09: "V"
        case 0x0A: "Section"
        case 0x0B: "B"
        case 0x0C: "Q"
        case 0x0D: "W"
        case 0x0E: "E"
        case 0x0F: "R"
        case 0x10: "Y"
        case 0x11: "T"
        case 0x12: "1"
        case 0x13: "2"
        case 0x14: "3"
        case 0x15: "4"
        case 0x16: "6"
        case 0x17: "5"
        case 0x18: "="
        case 0x19: "9"
        case 0x1A: "7"
        case 0x1B: "-"
        case 0x1C: "8"
        case 0x1D: "0"
        case 0x1E: "]"
        case 0x1F: "O"
        case 0x20: "U"
        case 0x21: "["
        case 0x22: "I"
        case 0x23: "P"
        case 0x24: "\u{21A9}" // Return
        case 0x25: "L"
        case 0x26: "J"
        case 0x27: "'"
        case 0x28: "K"
        case 0x29: ";"
        case 0x2A: "\\"
        case 0x2B: ","
        case 0x2C: "/"
        case 0x2D: "N"
        case 0x2E: "M"
        case 0x2F: "."
        case 0x30: "\u{21E5}" // Tab
        case 0x31: "\u{2423}" // Space
        case 0x32: "`"
        case 0x33: "\u{232B}" // Delete
        case 0x35: "\u{238B}" // Escape
        case 0x60: "F5"
        case 0x61: "F6"
        case 0x62: "F7"
        case 0x63: "F3"
        case 0x64: "F8"
        case 0x65: "F9"
        case 0x67: "F11"
        case 0x69: "F13"
        case 0x6B: "F14"
        case 0x6D: "F10"
        case 0x6F: "F12"
        case 0x71: "F15"
        case 0x76: "F4"
        case 0x78: "F2"
        case 0x7A: "F1"
        case 0x7B: "\u{2190}" // Left
        case 0x7C: "\u{2192}" // Right
        case 0x7D: "\u{2193}" // Down
        case 0x7E: "\u{2191}" // Up
        default: "Key(\(keyCode))"
        }
    }

    private static let reservedCombos: [(keyCode: UInt32, modifiers: UInt32)] = [
        (0x0C, UInt32(cmdKey)),                  // Cmd+Q
        (0x0D, UInt32(cmdKey)),                  // Cmd+W
        (0x30, UInt32(cmdKey)),                  // Cmd+Tab
        (0x31, UInt32(cmdKey)),                  // Cmd+Space
        (0x04, UInt32(cmdKey)),                  // Cmd+H
        (0x2E, UInt32(cmdKey)),                  // Cmd+M
        (0x0C, UInt32(cmdKey | shiftKey)),       // Cmd+Shift+Q
        (0x35, UInt32(cmdKey | optionKey)),       // Cmd+Opt+Esc
    ]

    static func isReserved(keyCode: UInt32, carbonModifiers: UInt32) -> Bool {
        let mods = carbonModifiers & UInt32(cmdKey | shiftKey | optionKey | controlKey)
        return reservedCombos.contains { $0.keyCode == keyCode && $0.modifiers == mods }
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }
}
