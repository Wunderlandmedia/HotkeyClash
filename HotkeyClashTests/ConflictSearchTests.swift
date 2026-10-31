import AppKit
import Testing
@testable import HotkeyClash

/// Tests for the field prefixes added for issue #2, plus the unprefixed search
/// they must leave alone.
@Suite("Conflict search", .bug(id: 2))
struct ConflictSearchTests {

    private func entry(_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags, app: String, action: String) -> ConflictSearch.Entry {
        ConflictSearch.entry(for: Conflict(keyCode: keyCode, modifiers: modifiers, bindings: [
            HotkeyBinding(keyCode: keyCode, modifiers: modifiers, ownerName: app, action: action, source: .menuBar)
        ]))
    }

    // Cmd+Z owned by "Ulysses" doing "Undo": the issue's exact pain, a "u"
    // everywhere except the key.
    private var undo: ConflictSearch.Entry { entry(0x06, [.command], app: "Ulysses", action: "Undo") }
    private var cmdU: ConflictSearch.Entry { entry(0x20, [.command], app: "Safari", action: "Show Page Source") }
    private var ctrlUp: ConflictSearch.Entry { entry(0x7E, [.control], app: "Mission Control", action: "Mission Control") }

    @Test("Unprefixed search still matches app, action, and combo")
    func unprefixedUnchanged() {
        #expect(ConflictSearch.matches(undo, query: "u"))
        #expect(ConflictSearch.matches(cmdU, query: "u"))
        #expect(ConflictSearch.matches(cmdU, query: "cmd u"))
        #expect(ConflictSearch.matches(undo, query: "cmd z ulysses"))
        #expect(ConflictSearch.matches(undo, query: "safari") == false)
    }

    @Test("key: matches only the key, and only the whole key name")
    func keyPrefix() {
        #expect(ConflictSearch.matches(cmdU, query: "key:u"))
        #expect(ConflictSearch.matches(undo, query: "key:u") == false)
        #expect(ConflictSearch.matches(ctrlUp, query: "key:u") == false)
        #expect(ConflictSearch.matches(ctrlUp, query: "key:up"))
        #expect(ConflictSearch.matches(ctrlUp, query: "KEY:Up"))
    }

    @Test("key: never matches a modifier word")
    func keyIgnoresModifiers() {
        #expect(ConflictSearch.matches(undo, query: "key:cmd") == false)
        #expect(ConflictSearch.matches(ctrlUp, query: "key:control") == false)
    }

    @Test("Punctuation keys stay searchable")
    func punctuationKey() {
        let comma = entry(0x2B, [.command], app: "Finder", action: "Settings")
        #expect(ConflictSearch.matches(comma, query: "key:,"))
    }

    @Test("app: and action: confine a prefix match to one field")
    func appAndActionPrefixes() {
        #expect(ConflictSearch.matches(undo, query: "app:uly"))
        #expect(ConflictSearch.matches(undo, query: "app:undo") == false)
        #expect(ConflictSearch.matches(undo, query: "action:undo"))
        #expect(ConflictSearch.matches(undo, query: "action:ulysses") == false)
        #expect(ConflictSearch.matches(cmdU, query: "action:source app:saf"))
    }

    @Test("Prefixed and plain tokens combine with AND")
    func mixedTokens() {
        #expect(ConflictSearch.matches(cmdU, query: "key:u cmd"))
        #expect(ConflictSearch.matches(cmdU, query: "key:u shift") == false)
    }

    @Test("A prefix with nothing after it filters nothing")
    func emptyPrefix() {
        #expect(ConflictSearch.matches(undo, query: "app:"))
        #expect(ConflictSearch.matches(undo, query: "key: undo"))
    }
}
