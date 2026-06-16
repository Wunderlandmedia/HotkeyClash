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

    /// Whether a conflict is an always-on clash or merely a focus-dependent overlap.
    enum ClashCategory {
        /// Involves at least one always-listening global hotkey (config file or
        /// system shortcut). It clashes regardless of which app is focused: two
        /// globals collide, or a global shadows an app's menu item so it never fires.
        case realConflict
        /// Only app menu shortcuts overlap (no global source). Each fires only when
        /// its own app is frontmost, so these do not actually clash in use. This is
        /// where the universal Copy/Paste/Quit boilerplate lands.
        case appOverlap
    }

    /// Classifies the conflict by whether any always-on global hotkey is involved.
    /// This is the source-based distinction that decides real clashes from menu noise,
    /// independent of how many apps happen to share the combo.
    var category: ClashCategory {
        let globalSources: Set<HotkeyBinding.BindingSource> = [.configFile, .systemShortcut]
        return bindings.contains { globalSources.contains($0.source) } ? .realConflict : .appOverlap
    }

    /// Number of distinct apps claiming this combo, keyed by bundle ID (falling back
    /// to name). Used to rank app overlaps: few-app overlaps are distinctive and rank
    /// high; universal boilerplate (Cmd+C across everything) sinks to the bottom.
    var appCount: Int {
        Set(bindings.map { $0.ownerBundleID ?? $0.ownerName }).count
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
