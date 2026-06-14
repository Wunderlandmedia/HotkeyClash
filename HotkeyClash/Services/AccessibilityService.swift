import ApplicationServices
import AppKit

// Pure Accessibility C-API calls with no shared mutable state, so this is
// nonisolated: the heavy menu traversal can run off the main actor (Apple also
// recommends not calling AX APIs on the main thread).
nonisolated enum AccessibilityService {

    // MARK: - Permission Check

    static func checkPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Menu Bar Scanning

    /// Returns the menu bar AXUIElement for the app with the given PID.
    /// Returns nil if the app has no menu bar or the AX query fails.
    static func getMenuBar(for pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var menuBar: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBar)
        // Verify the runtime type before casting. A misbehaving app can populate the
        // attribute with an unexpected CFType, and a force-cast on it would crash.
        guard result == .success, let menuBar,
              CFGetTypeID(menuBar) == AXUIElementGetTypeID() else { return nil }
        return (menuBar as! AXUIElement)
    }

    /// Returns the children of an AX element, or an empty array if the query fails.
    static func getChildren(of element: AXUIElement) -> [AXUIElement] {
        var children: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        guard result == .success, let array = children as? [AXUIElement] else { return [] }
        return array
    }

    /// Returns the title string of a menu item, or nil if unavailable.
    static func getTitle(of element: AXUIElement) -> String? {
        var title: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
        guard result == .success else { return nil }
        return title as? String
    }

    // MARK: - Menu Item Shortcut Extraction

    /// Extracts the keyboard shortcut assigned to a menu item.
    ///
    /// AX menu items expose shortcuts via two attributes:
    /// - `AXMenuItemCmdChar`: the character (e.g. "c", "v", "q")
    /// - `AXMenuItemCmdModifiers`: modifier flags in AX format
    ///
    /// AX modifier flags differ from NSEvent flags:
    /// - `0x00` = no extra modifiers (Command is always implied)
    /// - `0x01` = Shift
    /// - `0x02` = Option
    /// - `0x04` = Control
    /// - `0x08` = no Command (rare, means Command is NOT included)
    ///
    /// Returns nil if the menu item has no shortcut assigned.
    static func getMenuItemShortcut(from menuItem: AXUIElement) -> (character: String, modifiers: Int)? {
        var cmdChar: CFTypeRef?
        let charResult = AXUIElementCopyAttributeValue(menuItem, "AXMenuItemCmdChar" as CFString, &cmdChar)
        guard charResult == .success, let char = cmdChar as? String, !char.isEmpty else { return nil }

        var cmdMods: CFTypeRef?
        let modsResult = AXUIElementCopyAttributeValue(menuItem, "AXMenuItemCmdModifiers" as CFString, &cmdMods)
        let mods = modsResult == .success ? (cmdMods as? Int ?? 0) : 0

        return (character: char, modifiers: mods)
    }

    // MARK: - Modifier Conversion

    /// Converts AX menu item modifier flags to `NSEvent.ModifierFlags`.
    ///
    /// In AX menu items, Command is **always implied** unless the `0x08` flag is set
    /// (which explicitly excludes Command, though this is rare).
    static func convertAXModifiers(_ axMods: Int) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []

        // Command is implicit unless 0x08 flag is set
        if axMods & 0x08 == 0 {
            flags.insert(.command)
        }
        if axMods & 0x01 != 0 { flags.insert(.shift) }
        if axMods & 0x02 != 0 { flags.insert(.option) }
        if axMods & 0x04 != 0 { flags.insert(.control) }

        return flags
    }

    // MARK: - Character to KeyCode Mapping

    /// Converts a character string (from `AXMenuItemCmdChar`) to a macOS virtual key code.
    ///
    /// Maps common printable characters to their corresponding virtual key codes.
    /// Returns nil for unmapped characters (e.g., function keys, special symbols).
    static func keyCode(for character: String) -> UInt16? {
        let charToKeyCode: [String: UInt16] = [
            "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05,
            "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
            "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11,
            "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17,
            "=": 0x18, "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D,
            "]": 0x1E, "o": 0x1F, "u": 0x20, "[": 0x21, "i": 0x22, "p": 0x23,
            "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
            "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F,
        ]
        return charToKeyCode[character.lowercased()]
    }
}
