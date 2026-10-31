import AppKit

/// The matching rules behind the sidebar search, kept out of the view so they can
/// be tested.
///
/// A plain query searches everything at once: the spelled-out combo, app names,
/// and actions. That works until you want every combo on the U key and "u" also
/// pulls in "Undo", "Music", and every app starting with U (issue #2). So a token
/// can carry a prefix that confines it to one field: `key:u`, `app:finder`,
/// `action:copy`. Unprefixed tokens behave exactly as they always did.
enum ConflictSearch {

    /// One conflict's searchable words, split by field. Built once per scan, not
    /// per keystroke.
    struct Entry: Equatable {
        /// The spelled-out combo, modifiers and key ("command cmd shift c").
        var combo: [String]
        /// Just the key's words ("c", or "up arrow"), never the modifiers, so
        /// `key:c` cannot match a combo through "cmd" or "control".
        var key: [String]
        var apps: [String]
        var actions: [String]
    }

    static func entry(for conflict: Conflict) -> Entry {
        // Combo text splits on spaces only. Some keys are punctuation (",", "-"),
        // and the letters-only split used for names would erase them.
        let keyName = ShortcutFormatter.searchableKeyName(for: UInt32(conflict.keyCode))
        let combo: [String] = conflict.searchableText.split(separator: " ").map(String.init)
        let key: [String] = keyName.split(separator: " ").map(String.init)
        let apps: [String] = conflict.bindings.flatMap { words($0.ownerName) }
        let actions: [String] = conflict.bindings.flatMap { words($0.action) }
        return Entry(combo: combo, key: key, apps: apps, actions: actions)
    }

    /// Every whitespace-separated token must match (AND, any order). Words match
    /// by prefix, which keeps "p" from hitting the middle of "WhatsApp". The one
    /// exception is `key:`, which matches the whole key name: `key:u` asking for
    /// the U key should not also bring back the up arrow.
    static func matches(_ entry: Entry, query: String) -> Bool {
        tokens(in: query).allSatisfy { token in
            switch token {
            case .key(let term): entry.key.contains(term)
            case .app(let term): entry.apps.contains { $0.hasPrefix(term) }
            case .action(let term): entry.actions.contains { $0.hasPrefix(term) }
            case .any(let term): (entry.combo + entry.apps + entry.actions).contains { $0.hasPrefix(term) }
            }
        }
    }

    private enum Token {
        case key(String), app(String), action(String), any(String)
    }

    private static func tokens(in query: String) -> [Token] {
        let fields: [(prefix: String, make: (String) -> Token)] = [
            ("key:", Token.key), ("app:", Token.app), ("action:", Token.action),
        ]
        return query.lowercased().split(whereSeparator: \.isWhitespace).compactMap { raw -> Token? in
            let token = String(raw)
            for field in fields where token.hasPrefix(field.prefix) {
                let term = String(token.dropFirst(field.prefix.count))
                // A bare "app:" is someone halfway through typing. Treat it as no
                // filter at all rather than flashing an empty list at them.
                return term.isEmpty ? nil : field.make(term)
            }
            return .any(token)
        }
    }

    /// Lowercased letter-and-number words. Punctuation splits words, so
    /// "Copy Link" and "copy-link" both index as "copy" and "link".
    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}
