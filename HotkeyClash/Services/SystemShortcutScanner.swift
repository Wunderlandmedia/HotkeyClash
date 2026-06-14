import AppKit
import os

private let logger = Logger(subsystem: "com.hotkeyclash.app", category: "SystemShortcutScanner")

@MainActor
final class SystemShortcutScanner {

    func scan() -> [HotkeyBinding] {
        guard let defaults = UserDefaults(suiteName: "com.apple.symbolichotkeys"),
              let hotkeys = defaults.dictionary(forKey: "AppleSymbolicHotKeys") else {
            logger.warning("Could not read com.apple.symbolichotkeys")
            return []
        }

        var bindings: [HotkeyBinding] = []

        for (idString, value) in hotkeys {
            guard let entry = value as? [String: Any] else { continue }

            // Only include enabled shortcuts
            let enabled = entry["enabled"] as? Bool ?? false
            guard enabled else { continue }

            guard let valueDict = entry["value"] as? [String: Any],
                  let parameters = valueDict["parameters"] as? [Any],
                  parameters.count >= 3 else { continue }

            // parameters: [charOrFFFF, keyCode, carbonModifiers]
            guard let keyCodeValue = parameters[1] as? Int,
                  let carbonMods = parameters[2] as? Int else { continue }

            guard let keyCode = UInt16(exactly: keyCodeValue) else { continue }
            let modifiers = convertCarbonModifiers(carbonMods)

            // Skip entries with no key code (some system shortcuts have keyCode 65535 / 0xFFFF)
            if keyCode == 0xFFFF { continue }

            let shortcutID = Int(idString) ?? -1
            let name = shortcutNames[shortcutID] ?? "System Shortcut \(idString)"

            let binding = HotkeyBinding(
                keyCode: keyCode,
                modifiers: modifiers,
                ownerName: "macOS",
                ownerBundleID: "com.apple.systempreferences",
                action: name,
                source: .systemShortcut
            )
            bindings.append(binding)
        }

        logger.info("System shortcuts: found \(bindings.count) bindings")
        return bindings
    }

    // MARK: - Carbon Modifier Conversion

    /// Converts Carbon modifier flags from the symbolichotkeys plist to NSEvent.ModifierFlags.
    ///
    /// The plist stores modifiers as a bitmask using Carbon constants:
    /// - Bit 17 (131072)  = Shift
    /// - Bit 18 (262144)  = Control
    /// - Bit 19 (524288)  = Option
    /// - Bit 20 (1048576) = Command
    private func convertCarbonModifiers(_ carbonMods: Int) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonMods & 131072 != 0 { flags.insert(.shift) }
        if carbonMods & 262144 != 0 { flags.insert(.control) }
        if carbonMods & 524288 != 0 { flags.insert(.option) }
        if carbonMods & 1048576 != 0 { flags.insert(.command) }
        return flags
    }

    // MARK: - Known Shortcut Names

    /// Maps known symbolic hotkey IDs to human-readable names.
    private let shortcutNames: [Int: String] = [
        // Mission Control
        32: "Mission Control: All Windows",
        33: "Mission Control: Application Windows",
        34: "Mission Control: Show Desktop",
        36: "Move left a space",
        37: "Move right a space",
        62: "Mission Control: Move left a space",
        63: "Mission Control: Move right a space",
        79: "Mission Control: Switch to Desktop 1",
        80: "Mission Control: Switch to Desktop 2",
        81: "Mission Control: Switch to Desktop 3",
        82: "Mission Control: Switch to Desktop 4",

        // Input sources
        60: "Select previous input source",
        61: "Select next input source",

        // Spotlight
        64: "Show Spotlight search",
        65: "Show Finder search window",

        // Screenshots
        28: "Screenshot: Save picture of screen",
        29: "Screenshot: Copy picture of screen",
        30: "Screenshot: Save picture of selected area",
        31: "Screenshot: Copy picture of selected area",
        184: "Screenshot: Screenshot and recording options",

        // Accessibility
        118: "Focus Dock",
        162: "Focus menu bar",
        163: "Focus next window (accessibility)",
        175: "Focus next window (accessibility)",
        164: "Focus floating window",

        // App management
        27: "App Shortcuts: Move focus to next window",
        51: "App Shortcuts: Move focus to status menus",
        57: "App Shortcuts: Turn keyboard access on or off",

        // Display
        145: "Decrease display brightness",
        144: "Increase display brightness",

        // Dock
        52: "Turn Dock hiding on/off",

        // Keyboard brightness
        204: "Decrease keyboard brightness",
        205: "Increase keyboard brightness",
    ]
}
