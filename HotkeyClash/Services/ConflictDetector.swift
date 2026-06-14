import AppKit

/// Groups `HotkeyBinding` instances by key combo and identifies conflicts where
/// two or more bindings claim the same combination.
enum ConflictDetector {

    /// Takes all collected bindings and returns conflicts (groups of 2+ bindings on the same key combo).
    /// Sorted by severity (definite first), then by binding count (more clashes first).
    static func detect(bindings: [HotkeyBinding]) -> [Conflict] {
        // Group by (keyCode, normalizedModifiers) using rawValue for the dictionary key
        var groups: [UInt64: [HotkeyBinding]] = [:]

        for binding in bindings {
            let key = compositeKey(keyCode: binding.keyCode, modifiers: binding.normalizedModifiers)
            groups[key, default: []].append(binding)
        }

        // Filter to groups with 2+ bindings (actual conflicts)
        var conflicts: [Conflict] = []

        for (_, groupBindings) in groups {
            guard groupBindings.count >= 2 else { continue }

            let first = groupBindings[0]
            let conflict = Conflict(
                keyCode: first.keyCode,
                modifiers: first.normalizedModifiers,
                bindings: groupBindings
            )
            conflicts.append(conflict)
        }

        // Sort: definite severity first, then by binding count descending
        conflicts.sort { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }
            return lhs.bindings.count > rhs.bindings.count
        }

        return conflicts
    }

    /// Creates a composite key from keyCode and modifier flags for dictionary grouping.
    /// Packs keyCode (UInt16) into lower 16 bits and modifier rawValue into upper bits.
    private static func compositeKey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> UInt64 {
        UInt64(keyCode) | (UInt64(modifiers.rawValue) << 16)
    }
}
