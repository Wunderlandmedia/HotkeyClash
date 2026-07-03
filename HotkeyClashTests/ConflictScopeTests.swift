import AppKit
import Testing
@testable import HotkeyClash

/// Tests for the severity scope filter in the results header. The classification
/// itself is covered in ConflictClassificationTests; here we lock down which
/// classifications each scope lets through.
@Suite("Conflict scope filter")
struct ConflictScopeTests {

    // MARK: - Helpers

    private func binding(
        owner: String,
        source: HotkeyBinding.BindingSource
    ) -> HotkeyBinding {
        HotkeyBinding(
            keyCode: 0x0C, // Q
            modifiers: [.command],
            ownerName: owner,
            action: "\(owner) action",
            source: source
        )
    }

    private func conflict(_ bindings: [HotkeyBinding]) -> Conflict {
        Conflict(keyCode: bindings[0].keyCode, modifiers: bindings[0].normalizedModifiers, bindings: bindings)
    }

    /// A menu-only overlap: potential severity, appOverlap category.
    private var appOverlap: Conflict {
        conflict([
            binding(owner: "Safari", source: .menuBar),
            binding(owner: "Notes", source: .menuBar),
        ])
    }

    /// One global versus a menu item: potential severity, realConflict category.
    private var potentialReal: Conflict {
        conflict([
            binding(owner: "skhd", source: .configFile),
            binding(owner: "Safari", source: .menuBar),
        ])
    }

    /// Two globals: definite severity, realConflict category.
    private var definiteReal: Conflict {
        conflict([
            binding(owner: "skhd", source: .configFile),
            binding(owner: "System", source: .systemShortcut),
        ])
    }

    // MARK: - Matching

    @Test("All scope matches everything")
    func allMatchesEverything() {
        #expect(ConflictScope.all.matches(appOverlap))
        #expect(ConflictScope.all.matches(potentialReal))
        #expect(ConflictScope.all.matches(definiteReal))
    }

    @Test("Real conflicts scope hides app overlaps")
    func realConflictsHidesOverlaps() {
        #expect(!ConflictScope.realConflicts.matches(appOverlap))
        #expect(ConflictScope.realConflicts.matches(potentialReal))
        #expect(ConflictScope.realConflicts.matches(definiteReal))
    }

    @Test("Definite scope only matches two-global clashes")
    func definiteOnlyMatchesDefinite() {
        #expect(!ConflictScope.definiteOnly.matches(appOverlap))
        #expect(!ConflictScope.definiteOnly.matches(potentialReal))
        #expect(ConflictScope.definiteOnly.matches(definiteReal))
    }

    @Test("Every scope has a label and an empty message")
    func labelsAndEmptyMessages() {
        for scope in ConflictScope.allCases {
            #expect(!scope.label.isEmpty)
            #expect(!scope.emptyMessage.isEmpty)
        }
    }
}
