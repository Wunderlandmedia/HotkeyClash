import AppKit

/// Reports HotkeyClash's own panel shortcut as a binding, so the app is not blind
/// to itself.
///
/// Every other scanner reads someone else's registration. This one has nothing to
/// read: the shortcut is registered by `HotKeyManager` from `SettingsManager`, so
/// the setting is the record. Leaving it out meant the default Cmd+Shift+H never
/// showed up against Finder's "Go to Home Folder" on the same combo, which is a
/// real clash and, embarrassingly, one we caused ourselves.
///
/// Not gated behind a scan-source toggle. It is one binding we always know about,
/// and a user turning off "config files" is not asking to stop seeing it.
///
/// Takes the combo rather than reading `SettingsManager` itself, so the whole
/// thing stays a value in, value out helper like `ConflictReport`, and can be
/// tested without a live defaults store.
nonisolated struct OwnShortcutScanner {

    /// - Parameters:
    ///   - keyCode: virtual keycode of the registered shortcut.
    ///   - carbonModifiers: its modifiers in Carbon's masks, as stored in settings.
    func scan(keyCode: UInt32, carbonModifiers: UInt32) -> [HotkeyBinding] {
        [
            HotkeyBinding(
                keyCode: UInt16(keyCode),
                modifiers: ShortcutFormatter.modifierFlags(from: carbonModifiers),
                ownerName: "HotkeyClash",
                ownerBundleID: Bundle.main.bundleIdentifier,
                action: "Show the HotkeyClash panel",
                source: .globalHotkey
            )
        ]
    }
}
