import AppKit
import Testing
@testable import HotkeyClash

/// Tests for reading a search query as a key combo (issue #10). The parser has to
/// be strict: anything it wrongly accepts replaces the normal failed-search state.
@Suite("Combo lookup", .bug("https://github.com/Wunderlandmedia/HotkeyClash/issues/10"))
struct ComboLookupTests {

    // MARK: - Helpers

    private func binding(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        owner: String = "App",
        action: String = "Action"
    ) -> HotkeyBinding {
        HotkeyBinding(keyCode: keyCode, modifiers: modifiers, ownerName: owner, action: action, source: .menuBar)
    }

    // MARK: - Parsing

    @Test("Spelled-out, plus-joined, and glyph forms all parse to the same combo",
          arguments: ["opt cmd t", "cmd+option+T", "\u{2325}\u{2318}T", "alt command t"])
    func parsesCommonForms(query: String) throws {
        let combo = try #require(ComboLookup.parse(query))
        #expect(combo.keyCode == 0x11)
        #expect(combo.modifiers == [.command, .option])
    }

    @Test("Named keys use the same words as search")
    func namedKeys() {
        #expect(ComboLookup.parse("cmd space")?.keyCode == 0x31)
        #expect(ComboLookup.parse("ctrl cmd spacebar")?.keyCode == 0x31)
        #expect(ComboLookup.parse("cmd return")?.keyCode == 0x24)
        #expect(ComboLookup.parse("ctrl left arrow")?.keyCode == 0x7B)
        #expect(ComboLookup.parse("shift f5")?.keyCode == 0x60)
        #expect(ComboLookup.parse("cmd shift 4")?.keyCode == 0x15)
    }

    @Test("Globe is a modifier")
    func globe() {
        #expect(ComboLookup.parse("fn e")?.modifiers == .function)
    }

    @Test("Queries that are not a full combo stay plain text searches",
          arguments: ["t", "cmd", "cmd shift", "cmd safari", "cmd t r", "safari", ""])
    func rejectsNonCombos(query: String) {
        #expect(ComboLookup.parse(query) == nil)
    }

    // MARK: - Owners

    @Test("Owners match key and normalized modifiers exactly")
    func ownersMatchExactly() {
        let target = binding(keyCode: 0x11, modifiers: [.command, .option, .capsLock], owner: "Safari")
        let bindings = [
            target,
            binding(keyCode: 0x11, modifiers: [.command], owner: "Terminal"),
            binding(keyCode: 0x11, modifiers: [.command, .option, .shift], owner: "Xcode"),
        ]
        let owners = ComboLookup.owners(keyCode: 0x11, modifiers: [.command, .option], in: bindings)
        #expect(owners.map(\.ownerName) == ["Safari"])
    }

    @Test("An unused combo has no owners")
    func freeCombo() {
        let owners = ComboLookup.owners(keyCode: 0x11, modifiers: [.control], in: [binding(keyCode: 0x11, modifiers: [.command])])
        #expect(owners.isEmpty)
    }
}
