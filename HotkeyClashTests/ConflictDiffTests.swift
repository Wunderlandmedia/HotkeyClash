import AppKit
import Testing
@testable import HotkeyClash

/// Tests for the scan-to-scan diff. The identity rule (combo, not UUID) and the
/// first-scan-has-no-baseline behaviour are the two things that would silently
/// break the "N new" hint and the notification, so they're pinned here.
@Suite("Conflict diff")
struct ConflictDiffTests {

    // MARK: - Helpers

    private func binding(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [.command],
        owner: String,
        source: HotkeyBinding.BindingSource = .configFile
    ) -> HotkeyBinding {
        HotkeyBinding(
            keyCode: keyCode,
            modifiers: modifiers,
            ownerName: owner,
            ownerBundleID: nil,
            action: "Action",
            source: source
        )
    }

    /// A real (always-on) conflict on the given combo between two global sources.
    private func conflict(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [.command],
        owners: [String] = ["skhd", "Karabiner"]
    ) -> Conflict {
        let bindings = owners.map { binding(keyCode: keyCode, modifiers: modifiers, owner: $0) }
        return Conflict(keyCode: keyCode, modifiers: modifiers, bindings: bindings)
    }

    // MARK: - Baseline

    @Test("First scan has no baseline, so nothing is new")
    func firstScanReportsNothingNew() {
        let current = [conflict(keyCode: 0x31), conflict(keyCode: 0x0C)]
        let appeared = ConflictDiff.newlyAppeared(previous: nil, current: current)
        #expect(appeared.isEmpty)
    }

    @Test("Unchanged list reports nothing new")
    func unchangedReportsNothingNew() {
        let current = [conflict(keyCode: 0x31), conflict(keyCode: 0x0C)]
        let previous = Set(current.map(ConflictDiff.key(for:)))
        #expect(ConflictDiff.newlyAppeared(previous: previous, current: current).isEmpty)
    }

    // MARK: - Detecting new

    @Test("A combo absent from the baseline is reported as new")
    func newComboIsReported() {
        let old = conflict(keyCode: 0x31) // Space
        let previous: Set<UInt64> = [ConflictDiff.key(for: old)]

        let fresh = conflict(keyCode: 0x0C) // Q
        let appeared = ConflictDiff.newlyAppeared(previous: previous, current: [old, fresh])

        #expect(appeared.count == 1)
        #expect(appeared.first?.keyCode == 0x0C)
    }

    @Test("Same keyCode with different modifiers is a different conflict")
    func modifiersArePartOfIdentity() {
        let cmdSpace = conflict(keyCode: 0x31, modifiers: [.command])
        let previous: Set<UInt64> = [ConflictDiff.key(for: cmdSpace)]

        let cmdShiftSpace = conflict(keyCode: 0x31, modifiers: [.command, .shift])
        let appeared = ConflictDiff.newlyAppeared(previous: previous, current: [cmdSpace, cmdShiftSpace])

        #expect(appeared.count == 1)
        #expect(appeared.first?.modifiers == [.command, .shift])
    }

    @Test("A resolved conflict doesn't count as new")
    func resolvedIsNotNew() {
        let a = conflict(keyCode: 0x31)
        let b = conflict(keyCode: 0x0C)
        let previous = Set([a, b].map(ConflictDiff.key(for:)))

        // b is gone, a remains: nothing new appeared.
        let appeared = ConflictDiff.newlyAppeared(previous: previous, current: [a])
        #expect(appeared.isEmpty)
    }

    // MARK: - Notification wording

    @Test("Single new conflict names the combo and its apps")
    func singleNotificationText() {
        let c = conflict(keyCode: 0x0C, modifiers: [.command], owners: ["skhd", "Karabiner"])
        let text = ConflictDiff.notificationText(newConflicts: [c])
        #expect(text.title == "New shortcut conflict")
        #expect(text.body.contains("skhd"))
        #expect(text.body.contains("Karabiner"))
    }

    @Test("Two new conflicts join both combos")
    func twoNotificationText() {
        let text = ConflictDiff.notificationText(newConflicts: [
            conflict(keyCode: 0x0C), conflict(keyCode: 0x31)
        ])
        #expect(text.title == "2 new shortcut conflicts")
        #expect(text.body.contains(" and "))
        #expect(text.body.hasSuffix("now clash."))
    }

    @Test("Many new conflicts roll the tail into a count")
    func manyNotificationText() {
        let text = ConflictDiff.notificationText(newConflicts: [
            conflict(keyCode: 0x0C),
            conflict(keyCode: 0x31),
            conflict(keyCode: 0x0F),
            conflict(keyCode: 0x11)
        ])
        #expect(text.title == "4 new shortcut conflicts")
        #expect(text.body.contains("2 more"))
    }

    @Test("Duplicate app names collapse in the notification body")
    func duplicateOwnersCollapse() {
        // Same owner twice (two skhd bindings) should read once, not "skhd and skhd".
        let c = conflict(keyCode: 0x0C, owners: ["skhd", "skhd"])
        let text = ConflictDiff.notificationText(newConflicts: [c])
        #expect(text.body.contains("skhd"))
        #expect(!text.body.contains("skhd and skhd"))
    }
}
