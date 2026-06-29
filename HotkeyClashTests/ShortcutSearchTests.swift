import AppKit
import Testing
@testable import HotkeyClash

/// Tests that combos are searchable by spelled-out modifier and key names, not
/// just by the glyphs shown on screen. This is what lets a user type "shift".
@Suite("Shortcut search text")
struct ShortcutSearchTests {

    private func combo(_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags) -> String {
        Conflict(keyCode: keyCode, modifiers: modifiers, bindings: [
            HotkeyBinding(keyCode: keyCode, modifiers: modifiers, ownerName: "App", action: "Action", source: .menuBar)
        ]).searchableText
    }

    @Test("Modifiers are spelled out with synonyms")
    func modifierWords() {
        let text = combo(0x08, [.command, .shift]) // Cmd+Shift+C
        #expect(text.contains("command"))
        #expect(text.contains("cmd"))
        #expect(text.contains("shift"))
        #expect(text.contains("c"))
    }

    @Test("Option carries opt and alt synonyms")
    func optionSynonyms() {
        let text = combo(0x0F, [.option]) // Option+R
        #expect(text.contains("option"))
        #expect(text.contains("opt"))
        #expect(text.contains("alt"))
    }

    @Test("Glyph keys get word forms")
    func glyphKeyWords() {
        #expect(combo(0x31, [.command]).contains("space"))   // Cmd+Space
        #expect(combo(0x24, [.command]).contains("return"))  // Cmd+Return
        #expect(combo(0x7E, [.control]).contains("up arrow")) // Ctrl+Up
    }
}
