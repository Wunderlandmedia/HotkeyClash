import AppKit

/// Compares the conflicts from one scan against the last, so the app can tell the
/// user what actually changed instead of just re-presenting the whole list.
///
/// Identity is the key combo itself (keyCode + modifiers), never the `Conflict`'s
/// `id`, which is minted fresh on every scan. Two scans that both flag Cmd+Space
/// are the same conflict even though their UUIDs differ. The packing here matches
/// what `ConflictDetector` uses internally to group bindings.
///
/// Pure value-in, value-out. The scanner feeds it real conflicts only (the
/// always-on ones); focus-dependent menu overlaps churn every time an app opens
/// or closes, so counting those as "new" would be noise, not news.
enum ConflictDiff {

    /// Stable cross-scan key for a conflict: keyCode in the low 16 bits, the
    /// normalized modifier rawValue above it.
    static func key(for conflict: Conflict) -> UInt64 {
        UInt64(conflict.keyCode) | (UInt64(conflict.modifiers.rawValue) << 16)
    }

    /// Conflicts present in `current` but absent from `previous`. A nil `previous`
    /// means there is no baseline yet (the first scan of the session), so nothing
    /// counts as newly appeared. Order follows `current`.
    static func newlyAppeared(previous: Set<UInt64>?, current: [Conflict]) -> [Conflict] {
        guard let previous else { return [] }
        return current.filter { !previous.contains(key(for: $0)) }
    }

    /// Title and body for the "new conflicts" notification. Pure so the wording
    /// stays under test without standing up UserNotifications. Expects a non-empty
    /// list (the caller only posts when something appeared).
    static func notificationText(newConflicts: [Conflict]) -> (title: String, body: String) {
        let combos = newConflicts.map(\.displayString)

        if newConflicts.count == 1 {
            let apps = ownerList(newConflicts[0])
            return (
                title: "New shortcut conflict",
                body: "\(combos[0]) is now claimed by \(apps)."
            )
        }

        let title = "\(newConflicts.count) new shortcut conflicts"
        // Name the first couple of combos and roll the rest into a count, so the
        // banner stays short no matter how many appeared at once.
        let body: String
        switch combos.count {
        case 2:
            body = "\(combos[0]) and \(combos[1]) now clash."
        case 3:
            body = "\(combos[0]), \(combos[1]) and \(combos[2]) now clash."
        default:
            let shown = combos.prefix(2).joined(separator: ", ")
            body = "\(shown) and \(combos.count - 2) more now clash."
        }
        return (title: title, body: body)
    }

    /// The distinct app names in a conflict, joined for prose ("A and B", "A, B
    /// and C"). Keyed by bundle id where present so the same app listed twice
    /// collapses to one name.
    private static func ownerList(_ conflict: Conflict) -> String {
        var seen: Set<String> = []
        var names: [String] = []
        for binding in conflict.bindings {
            let key = binding.ownerBundleID ?? binding.ownerName
            if seen.insert(key).inserted {
                names.append(binding.ownerName)
            }
        }

        switch names.count {
        case 0: return "another app"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default:
            let head = names.dropLast().joined(separator: ", ")
            return "\(head) and \(names[names.count - 1])"
        }
    }
}
