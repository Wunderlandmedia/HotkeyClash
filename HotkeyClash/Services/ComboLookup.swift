import AppKit

/// Answers "what uses this combo?" for a search query that spells out a shortcut.
///
/// The conflict list only shows clashes, so a search for a combo that one app
/// owns alone used to come back empty, and people read that as "not scanned"
/// (issues #3 and #10). The scan already holds every binding. When a query reads
/// as a key combo, this looks it up there, so the empty state can say who owns
/// it or that it is free. Only a combo query does this. Searching an app name
/// still returns conflicts only, so this never turns into a browsable list of
/// every shortcut, which is KeyClu's job.
enum ComboLookup {

    /// Parses a query like "opt cmd t", "cmd+shift+4", or "⌥⌘T" into a combo.
    /// Returns nil unless every token is a modifier or a key name, there is exactly
    /// one key, and at least one modifier. The modifier rule keeps a bare "t" or
    /// "safari" from being read as a combo; the every-token rule keeps "cmd safari"
    /// a plain text search.
    static func parse(_ query: String) -> (keyCode: UInt16, modifiers: NSEvent.ModifierFlags)? {
        var text = query.lowercased()
        // Glyphs and "+" become spaces around words, so "⌥⌘t" and "cmd+t" split
        // the same way "opt cmd t" does.
        for (glyph, word) in [("\u{2318}", "cmd"), ("\u{2325}", "opt"), ("\u{21E7}", "shift"), ("\u{2303}", "ctrl"), ("+", "")] {
            text = text.replacingOccurrences(of: glyph, with: " \(word) ")
        }

        var modifiers: NSEvent.ModifierFlags = []
        var keyCode: UInt16?
        for token in text.split(whereSeparator: \.isWhitespace).map(String.init) {
            if let flag = modifierWords[token] {
                modifiers.insert(flag)
            } else if token == "arrow" {
                // "left arrow" is how the search text spells it; "left" alone
                // already names the key.
                continue
            } else if let code = keyCodes[token], keyCode == nil {
                keyCode = code
            } else {
                return nil
            }
        }

        guard let keyCode, !modifiers.isEmpty else { return nil }
        return (keyCode, modifiers)
    }

    /// Every scanned binding on the combo, matched the same way `ConflictDetector`
    /// groups them, so a lookup and the conflict list never disagree.
    static func owners(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, in bindings: [HotkeyBinding]) -> [HotkeyBinding] {
        bindings.filter { $0.keyCode == keyCode && $0.normalizedModifiers == modifiers }
    }

    private static let modifierWords: [String: NSEvent.ModifierFlags] = [
        "cmd": .command, "command": .command,
        "opt": .option, "option": .option, "alt": .option,
        "shift": .shift,
        "ctrl": .control, "control": .control,
        "globe": .function, "fn": .function, "function": .function,
    ]

    /// Key name to keycode, read back out of `ShortcutFormatter` so there is still
    /// one place that knows what each key is called. Both the display name ("t",
    /// "f5", "↩") and the spelled-out search words ("return", "enter") count.
    private static let keyCodes: [String: UInt16] = {
        var map: [String: UInt16] = [:]
        for code in UInt32(0)...0x7F {
            let name = ShortcutFormatter.keyName(for: code)
            guard !name.hasPrefix("Key(") else { continue }
            map[name.lowercased()] = UInt16(code)
            for word in ShortcutFormatter.searchableKeyName(for: code).split(separator: " ") where word != "arrow" {
                map[String(word)] = UInt16(code)
            }
        }
        return map
    }()
}
