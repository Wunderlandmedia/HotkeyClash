import AppKit

/// A single keyboard shortcut registration from any source (menu bar, config file, or system).
///
/// Marked `nonisolated` (rather than inheriting the module's default main-actor
/// isolation) so it can be built off the main actor during the Accessibility scan
/// and cross actor boundaries as an inferred-`Sendable` value type.
nonisolated struct HotkeyBinding: Identifiable, Hashable {
    let id: UUID
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    let ownerName: String
    let ownerBundleID: String?
    let action: String
    let source: BindingSource

    enum BindingSource: String, CaseIterable {
        case menuBar
        case configFile
        case systemShortcut
    }

    init(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        ownerName: String,
        ownerBundleID: String? = nil,
        action: String,
        source: BindingSource
    ) {
        self.id = UUID()
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.ownerName = ownerName
        self.ownerBundleID = ownerBundleID
        self.action = action
        self.source = source
    }

    /// Strips device-specific flags, keeping only the four standard modifiers.
    /// Used for grouping bindings by key combo regardless of capsLock, numericPad, etc.
    var normalizedModifiers: NSEvent.ModifierFlags {
        modifiers.intersection([.command, .option, .shift, .control])
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(normalizedModifiers.rawValue)
        hasher.combine(ownerName)
        hasher.combine(action)
    }

    static func == (lhs: HotkeyBinding, rhs: HotkeyBinding) -> Bool {
        lhs.keyCode == rhs.keyCode &&
        lhs.normalizedModifiers == rhs.normalizedModifiers &&
        lhs.ownerName == rhs.ownerName &&
        lhs.action == rhs.action
    }
}
