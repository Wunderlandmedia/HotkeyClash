import AppKit

/// Two or more `HotkeyBinding` instances that claim the same key combination.
struct Conflict: Identifiable, Equatable {
    nonisolated static func == (lhs: Conflict, rhs: Conflict) -> Bool {
        lhs.id == rhs.id
    }

    let id: UUID
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    let bindings: [HotkeyBinding]

    enum Severity: Comparable {
        /// Global hotkey overlaps a per-app menu shortcut.
        /// Only clashes when that specific app is focused.
        case potential
        /// Two global hotkeys on the same combo. Guaranteed clash.
        case definite
    }

    /// Classifies severity based on how many bindings come from global sources.
    /// Two or more global sources (config files or system shortcuts) means a definite clash.
    /// Otherwise it is a potential clash (global vs per-app menu item).
    var severity: Severity {
        let globalSources: Set<HotkeyBinding.BindingSource> = [.configFile, .systemShortcut]
        let globalCount = bindings.filter { globalSources.contains($0.source) }.count
        return globalCount >= 2 ? .definite : .potential
    }

    /// Human-readable display string for the key combo (e.g. "\u{2318}\u{21E7}G").
    var displayString: String {
        ShortcutFormatter.displayString(
            keyCode: UInt32(keyCode),
            carbonModifiers: ShortcutFormatter.carbonModifiers(from: modifiers)
        )
    }

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, bindings: [HotkeyBinding]) {
        self.id = UUID()
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.bindings = bindings
    }
}
