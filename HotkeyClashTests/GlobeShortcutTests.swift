import AppKit
import Testing
@testable import HotkeyClash

/// Globe (fn) menu shortcuts, which the app used to flatten into bare keys.
///
/// The values here are not invented: TextEdit's "Emoji & Symbols" really does
/// report `AXMenuItemCmdChar` "E" with `AXMenuItemCmdModifiers` 24, which is the
/// 0x08 "no Command" flag plus the undocumented 0x10 Globe flag.
@Suite("Globe shortcuts", .bug("https://github.com/Wunderlandmedia/HotkeyClash/issues/5"))
struct GlobeShortcutTests {

    private func binding(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        owner: String
    ) -> HotkeyBinding {
        HotkeyBinding(
            keyCode: keyCode,
            modifiers: modifiers,
            ownerName: owner,
            ownerBundleID: nil,
            action: "Action",
            source: .menuBar
        )
    }

    // MARK: - Reading the AX flags

    @Test("The Emoji and Symbols item decodes as Globe plus E, with no Command")
    func emojiAndSymbols() {
        let flags = AccessibilityService.convertAXModifiers(24)
        #expect(flags.contains(.function))
        #expect(flags.contains(.command) == false)
        #expect(flags.intersection([.shift, .option, .control]).isEmpty)
    }

    @Test("Globe combines with the ordinary modifiers", arguments: [
        (0x10 | 0x01, NSEvent.ModifierFlags([.command, .shift, .function])),
        (0x10 | 0x08, NSEvent.ModifierFlags([.function])),
        (0x10 | 0x04 | 0x08, NSEvent.ModifierFlags([.control, .function]))
    ])
    func globeWithOthers(axMods: Int, expected: NSEvent.ModifierFlags) {
        #expect(AccessibilityService.convertAXModifiers(axMods) == expected)
    }

    @Test("A shortcut without the Globe bit is unaffected")
    func withoutGlobe() {
        #expect(AccessibilityService.convertAXModifiers(0x01).contains(.function) == false)
    }

    // MARK: - Not a bare key

    @Test("Globe survives normalization, so it still counts as a modifier")
    func normalizationKeepsGlobe() {
        let globeE = binding(keyCode: 0x0E, modifiers: [.function], owner: "TextEdit")
        #expect(globeE.normalizedModifiers == [.function])
    }

    @Test("Globe plus E does not clash with a plain E")
    func doesNotGroupWithBareKey() {
        // The actual bug: with Globe dropped, these two grouped together and the
        // app reported a conflict that no keypress could ever produce.
        let conflicts = ConflictDetector.detect(bindings: [
            binding(keyCode: 0x0E, modifiers: [.function], owner: "TextEdit"),
            binding(keyCode: 0x0E, modifiers: [], owner: "Some App")
        ])
        #expect(conflicts.isEmpty)
    }

    @Test("Two Globe shortcuts on the same key still clash")
    func globeShortcutsStillClash() {
        let conflicts = ConflictDetector.detect(bindings: [
            binding(keyCode: 0x0E, modifiers: [.function], owner: "TextEdit"),
            binding(keyCode: 0x0E, modifiers: [.function], owner: "Notes")
        ])
        #expect(conflicts.count == 1)
    }

    // MARK: - Display and search

    @Test("Globe combos read as Globe, not as a bare letter")
    func display() {
        let conflict = Conflict(keyCode: 0x0E, modifiers: [.function], bindings: [])
        #expect(conflict.displayString == "Globe E")
    }

    @Test("Globe sits in front of the other modifier glyphs")
    func displayWithOtherModifiers() {
        let conflict = Conflict(keyCode: 0x0E, modifiers: [.function, .shift], bindings: [])
        #expect(conflict.displayString == "Globe \u{21E7}E")
    }

    @Test("Searching for globe, fn, or function finds the combo", arguments: ["globe", "fn", "function"])
    func searchable(term: String) {
        let conflict = Conflict(keyCode: 0x0E, modifiers: [.function], bindings: [])
        #expect(conflict.searchableText.contains(term))
    }

    @Test("A combo without Globe gains no globe words")
    func searchableWithoutGlobe() {
        let conflict = Conflict(keyCode: 0x0E, modifiers: [.command], bindings: [])
        #expect(conflict.searchableText.contains("globe") == false)
    }
}
