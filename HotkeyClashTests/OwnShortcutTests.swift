import AppKit
import Carbon
import Testing
@testable import HotkeyClash

/// Covers the app reporting its own panel shortcut: the modifier round trip that
/// makes it possible, and the classification that decides how the result reads.
///
/// Issue #4: the default Cmd+Shift+H sits on top of Finder's "Go to Home Folder"
/// and HotkeyClash listed everyone's shortcuts but its own.
@Suite("Own shortcut", .bug("https://github.com/Wunderlandmedia/HotkeyClash/issues/4"))
struct OwnShortcutTests {

    private func binding(
        owner: String,
        source: HotkeyBinding.BindingSource
    ) -> HotkeyBinding {
        HotkeyBinding(
            keyCode: 0x04,
            modifiers: [.command, .shift],
            ownerName: owner,
            ownerBundleID: nil,
            action: "Action",
            source: source
        )
    }

    // MARK: - Modifier round trip

    /// Spelled out as a typed constant rather than inline in the `arguments:`
    /// list: the mixed UInt32 / OptionSet literals made the type checker give up.
    static let modifierCases: [(carbon: UInt32, flags: NSEvent.ModifierFlags)] = [
        (UInt32(cmdKey), .command),
        (UInt32(shiftKey), .shift),
        (UInt32(optionKey), .option),
        (UInt32(controlKey), .control),
        (UInt32(cmdKey | shiftKey), [.command, .shift]),
        (0, [])
    ]

    @Test("Carbon masks convert back to Cocoa flags", arguments: modifierCases)
    func carbonToFlags(carbon: UInt32, expected: NSEvent.ModifierFlags) {
        #expect(ShortcutFormatter.modifierFlags(from: carbon) == expected)
    }

    @Test("Every modifier survives a round trip in both directions")
    func roundTrip() {
        let flags: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let carbon = ShortcutFormatter.carbonModifiers(from: flags)
        #expect(ShortcutFormatter.modifierFlags(from: carbon) == flags)
    }

    // MARK: - The scanner

    @Test("The scanner reports the registered combo as one global hotkey binding")
    func scannerEmitsTheShortcut() throws {
        let bindings = OwnShortcutScanner().scan(keyCode: 0x04, carbonModifiers: UInt32(cmdKey | shiftKey))
        let binding = try #require(bindings.first)
        #expect(bindings.count == 1)
        #expect(binding.keyCode == 0x04)
        #expect(binding.normalizedModifiers == [.command, .shift])
        #expect(binding.ownerName == "HotkeyClash")
        #expect(binding.source == .globalHotkey)
    }

    @Test("A rebound shortcut is reported, not the default")
    func scannerFollowsTheSetting() throws {
        let bindings = OwnShortcutScanner().scan(keyCode: 0x31, carbonModifiers: UInt32(controlKey | optionKey))
        let binding = try #require(bindings.first)
        #expect(binding.keyCode == 0x31)
        #expect(binding.normalizedModifiers == [.control, .option])
    }

    // MARK: - Classification

    @Test("A registered global hotkey lands on the Carbon layer")
    func layer() {
        #expect(HotkeyLayer.classify(binding(owner: "HotkeyClash", source: .globalHotkey)) == .globalHotKey)
    }

    @Test("Our shortcut against an app menu item is a real conflict")
    func clashWithMenuItem() {
        let conflict = Conflict(
            keyCode: 0x04,
            modifiers: [.command, .shift],
            bindings: [
                binding(owner: "HotkeyClash", source: .globalHotkey),
                binding(owner: "Finder", source: .menuBar)
            ]
        )
        // The whole point of the issue: a global hotkey shadows the menu item, so
        // this has to count as real rather than sinking into the menu-overlap noise.
        #expect(conflict.category == .realConflict)
        #expect(conflict.severity == .potential)
    }

    @Test("Our shortcut against a system shortcut is a definite clash")
    func clashWithSystemShortcut() {
        let conflict = Conflict(
            keyCode: 0x04,
            modifiers: [.command, .shift],
            bindings: [
                binding(owner: "HotkeyClash", source: .globalHotkey),
                binding(owner: "macOS", source: .systemShortcut)
            ]
        )
        #expect(conflict.severity == .definite)
    }

    @Test("The likely winner is decided by layer, not by who we are")
    func doesNotWinAgainstAnEventTap() {
        let ours = binding(owner: "HotkeyClash", source: .globalHotkey)
        let skhd = binding(owner: "skhd", source: .configFile)
        #expect(LikelyWinner.evaluate([ours, skhd]) == .likely(skhd, layer: .eventTap))
    }
}
