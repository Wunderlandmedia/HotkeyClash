import AppKit
import Testing
@testable import HotkeyClash

/// Tests for grouping bindings into conflicts by key combo, and the sort order.
@MainActor
@Suite("Conflict detection")
struct ConflictDetectorTests {

    private func binding(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        owner: String,
        source: HotkeyBinding.BindingSource
    ) -> HotkeyBinding {
        HotkeyBinding(keyCode: keyCode, modifiers: modifiers, ownerName: owner, action: "act", source: source)
    }

    @Test("A combo claimed by only one binding is not a conflict")
    func singleBindingIsNoConflict() {
        let conflicts = ConflictDetector.detect(bindings: [
            binding(keyCode: 0x0C, modifiers: [.command], owner: "Solo", source: .menuBar)
        ])
        #expect(conflicts.isEmpty)
    }

    @Test("Same combo from two apps forms one conflict")
    func sameComboGroups() {
        let conflicts = ConflictDetector.detect(bindings: [
            binding(keyCode: 0x0C, modifiers: [.command], owner: "A", source: .menuBar),
            binding(keyCode: 0x0C, modifiers: [.command], owner: "B", source: .menuBar),
        ])
        #expect(conflicts.count == 1)
        #expect(conflicts[0].bindings.count == 2)
    }

    @Test("Different modifiers do not group together")
    func differentModifiersStaySeparate() {
        let conflicts = ConflictDetector.detect(bindings: [
            binding(keyCode: 0x0C, modifiers: [.command], owner: "A", source: .menuBar),
            binding(keyCode: 0x0C, modifiers: [.command, .shift], owner: "B", source: .menuBar),
        ])
        #expect(conflicts.isEmpty)
    }

    @Test("Device-specific flags are ignored when grouping")
    func normalizedModifiersGroup() {
        // capsLock differs but the four standard modifiers match, so these collide.
        let conflicts = ConflictDetector.detect(bindings: [
            binding(keyCode: 0x0C, modifiers: [.command], owner: "A", source: .menuBar),
            binding(keyCode: 0x0C, modifiers: [.command, .capsLock], owner: "B", source: .menuBar),
        ])
        #expect(conflicts.count == 1)
        #expect(conflicts[0].bindings.count == 2)
    }

    @Test("Definite conflicts sort ahead of potential ones")
    func definiteSortsFirst() {
        let conflicts = ConflictDetector.detect(bindings: [
            // Potential: menu-only overlap on Cmd+W
            binding(keyCode: 0x0D, modifiers: [.command], owner: "A", source: .menuBar),
            binding(keyCode: 0x0D, modifiers: [.command], owner: "B", source: .menuBar),
            // Definite: two globals on Cmd+Q
            binding(keyCode: 0x0C, modifiers: [.command], owner: "skhd", source: .configFile),
            binding(keyCode: 0x0C, modifiers: [.command], owner: "sys", source: .systemShortcut),
        ])
        #expect(conflicts.count == 2)
        #expect(conflicts.first?.severity == .definite)
    }
}
