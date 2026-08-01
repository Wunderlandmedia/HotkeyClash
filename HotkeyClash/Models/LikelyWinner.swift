import Foundation

/// A static best guess at which binding actually receives a key combo.
///
/// This is the cheap answer to the question everyone asks first: "fine, but who
/// actually wins?" It reasons purely from `HotkeyLayer`, which means it is right
/// often and honest when it cannot be. Where the layers tie, we say so rather
/// than picking a name and hoping, because the tiebreaker is registration order
/// and nothing on disk records that.
nonisolated enum LikelyWinner: Equatable {
    /// One binding sits strictly lower in the event stack than every other.
    case likely(HotkeyBinding, layer: HotkeyLayer)
    /// Several bindings share the lowest layer, so registration order decides.
    case tied([HotkeyBinding], layer: HotkeyLayer)
    /// Nothing global is involved: only app menu items, so whichever app is
    /// frontmost wins and there is nothing to resolve.
    case focusDependent

    /// Works out the verdict for a set of bindings on the same combo.
    /// Returns nil only for an empty set, which a real conflict never is.
    static func evaluate(_ bindings: [HotkeyBinding]) -> LikelyWinner? {
        guard !bindings.isEmpty else { return nil }

        let layers = bindings.map { ($0, HotkeyLayer.classify($0)) }
        guard let lowest = layers.map(\.1).min() else { return nil }

        // Menu items are the top of the stack, so if that is the lowest layer
        // present then every binding is a menu item and none of them compete.
        if lowest == .menuItem { return .focusDependent }

        let contenders = layers.filter { $0.1 == lowest }.map(\.0)
        if contenders.count == 1 {
            return .likely(contenders[0], layer: lowest)
        }
        return .tied(contenders, layer: lowest)
    }

    /// Plain-language verdict, used verbatim in the detail pane and the export.
    var summary: String {
        switch self {
        case .likely(let binding, let layer):
            "\(binding.ownerName) most likely wins. \(layer.explanation)"
        case .tied(let bindings, let layer):
            "\(joined(bindings.map(\.ownerName))) all hook the same layer, so whichever registered first wins. That order is not recorded anywhere HotkeyClash can read. \(layer.explanation)"
        case .focusDependent:
            "Whichever app is frontmost wins. These are all menu shortcuts, so they never compete for the same keypress."
        }
    }

    /// The binding to mark in the list, when there is a single clear favourite.
    var winningBindingID: UUID? {
        if case .likely(let binding, _) = self { return binding.id }
        return nil
    }

    private func joined(_ names: [String]) -> String {
        var seen: Set<String> = []
        let unique = names.filter { seen.insert($0).inserted }
        switch unique.count {
        case 0: return ""
        case 1: return unique[0]
        case 2: return "\(unique[0]) and \(unique[1])"
        default: return unique.dropLast().joined(separator: ", ") + ", and \(unique[unique.count - 1])"
        }
    }
}
