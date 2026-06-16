import AppKit
import Testing
@testable import HotkeyClash

/// Tests for how a Conflict is classified: real (always-on) vs app overlap
/// (focus-dependent), and its severity. This is the logic that drives the
/// results filter, so it is locked down here rather than verified by eye.
@Suite("Conflict classification")
struct ConflictClassificationTests {

    // MARK: - Helpers

    private func binding(
        keyCode: UInt16 = 0x0C, // Q
        modifiers: NSEvent.ModifierFlags = [.command],
        owner: String = "App",
        bundleID: String? = nil,
        source: HotkeyBinding.BindingSource
    ) -> HotkeyBinding {
        HotkeyBinding(
            keyCode: keyCode,
            modifiers: modifiers,
            ownerName: owner,
            ownerBundleID: bundleID,
            action: "\(owner) action",
            source: source
        )
    }

    private func conflict(_ bindings: [HotkeyBinding]) -> Conflict {
        Conflict(keyCode: bindings[0].keyCode, modifiers: bindings[0].normalizedModifiers, bindings: bindings)
    }

    // MARK: - Category

    @Test("Menu-only overlap is an app overlap, not a real conflict")
    func menuOnlyIsAppOverlap() {
        let c = conflict([
            binding(owner: "Safari", source: .menuBar),
            binding(owner: "Ollama", source: .menuBar),
            binding(owner: "Notes", source: .menuBar),
        ])
        #expect(c.category == .appOverlap)
    }

    @Test("A config-file binding makes it a real conflict")
    func configFileIsRealConflict() {
        let c = conflict([
            binding(owner: "skhd", source: .configFile),
            binding(owner: "Safari", source: .menuBar),
        ])
        #expect(c.category == .realConflict)
    }

    @Test("A system shortcut makes it a real conflict")
    func systemShortcutIsRealConflict() {
        let c = conflict([
            binding(owner: "System", source: .systemShortcut),
            binding(owner: "Safari", source: .menuBar),
        ])
        #expect(c.category == .realConflict)
    }

    @Test("Many menu apps sharing a combo is still only an app overlap")
    func manyMenuAppsStillAppOverlap() {
        // The universal Cmd+Q across dozens of apps must not be promoted to a real
        // conflict just because many apps share it: each only fires when focused.
        let bindings = (0..<30).map { binding(owner: "App\($0)", source: .menuBar) }
        #expect(conflict(bindings).category == .appOverlap)
    }

    // MARK: - Severity

    @Test("Two global sources is a definite conflict")
    func twoGlobalsAreDefinite() {
        let c = conflict([
            binding(owner: "skhd", source: .configFile),
            binding(owner: "System", source: .systemShortcut),
        ])
        #expect(c.severity == .definite)
    }

    @Test("One global plus menu items is a potential conflict")
    func oneGlobalIsPotential() {
        let c = conflict([
            binding(owner: "skhd", source: .configFile),
            binding(owner: "Safari", source: .menuBar),
        ])
        #expect(c.severity == .potential)
    }
}
