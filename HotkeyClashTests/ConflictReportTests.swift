import AppKit
import Testing
@testable import HotkeyClash

/// Tests for the Markdown export. The report is what users share in bug reports,
/// so its structure (sections, severity, per-app lines) is locked down here.
@Suite("Conflict report")
struct ConflictReportTests {

    // MARK: - Helpers

    private func binding(
        keyCode: UInt16 = 0x0C, // Q
        modifiers: NSEvent.ModifierFlags = [.command],
        owner: String,
        action: String = "Action",
        source: HotkeyBinding.BindingSource
    ) -> HotkeyBinding {
        HotkeyBinding(
            keyCode: keyCode,
            modifiers: modifiers,
            ownerName: owner,
            ownerBundleID: nil,
            action: action,
            source: source
        )
    }

    private func conflict(_ bindings: [HotkeyBinding]) -> Conflict {
        Conflict(keyCode: bindings[0].keyCode, modifiers: bindings[0].normalizedModifiers, bindings: bindings)
    }

    // MARK: - Empty

    @Test("Empty scan reports no conflicts")
    func emptyReport() {
        let md = ConflictReport.markdown(conflicts: [], bindingCount: 120, scanDuration: 0.4)
        #expect(md.contains("# HotkeyClash Conflict Report"))
        #expect(md.contains("No conflicts found."))
        #expect(md.contains("Scanned 120 shortcuts"))
        #expect(!md.contains("## Real conflicts"))
    }

    // MARK: - Sections

    @Test("Real conflicts and menu overlaps land in their own sections")
    func sectionsByCategory() {
        let real = conflict([
            binding(owner: "skhd", source: .configFile),
            binding(owner: "System", action: "Spotlight", source: .systemShortcut),
        ])
        let overlap = conflict([
            binding(keyCode: 0x08, owner: "Safari", action: "Copy", source: .menuBar),
            binding(keyCode: 0x08, owner: "Notes", action: "Copy", source: .menuBar),
        ])

        let md = ConflictReport.markdown(conflicts: [real, overlap], bindingCount: 50, scanDuration: 1.0)

        #expect(md.contains("## Real conflicts"))
        #expect(md.contains("## Menu overlaps"))
        #expect(md.contains("Found 1 real conflict and 1 menu overlap."))
        #expect(md.contains("Definite conflict"))
    }

    @Test("Each binding renders an app, source label, and action")
    func bindingLines() {
        let c = conflict([
            binding(owner: "skhd", action: "Focus left", source: .configFile),
            binding(owner: "System", action: "Mission Control", source: .systemShortcut),
        ])

        let md = ConflictReport.markdown(conflicts: [c], bindingCount: 2, scanDuration: 0.1)

        #expect(md.contains("**System** (System): Mission Control"))
        #expect(md.contains("**skhd** (Config): Focus left"))
    }

    @Test("Report avoids em dashes per project convention")
    func noEmDashes() {
        let c = conflict([
            binding(owner: "skhd", source: .configFile),
            binding(owner: "System", source: .systemShortcut),
        ])
        let md = ConflictReport.markdown(conflicts: [c], bindingCount: 2, scanDuration: 0.1)
        #expect(!md.contains("\u{2014}"))
    }
}
