import AppKit
import Testing
@testable import HotkeyClash

/// Tests for the likely-winner verdict. The interesting cases are the ones where
/// it declines to answer: a tie has to stay a tie, because guessing there would
/// be worse than saying nothing.
@Suite("Likely winner")
struct LikelyWinnerTests {

    // MARK: - Helpers

    private func binding(
        owner: String,
        bundleID: String? = nil,
        source: HotkeyBinding.BindingSource
    ) -> HotkeyBinding {
        HotkeyBinding(
            keyCode: 0x31, // Space
            modifiers: [.command],
            ownerName: owner,
            ownerBundleID: bundleID,
            action: "Action",
            source: source
        )
    }

    private func karabiner() -> HotkeyBinding {
        binding(owner: "Karabiner-Elements", bundleID: "org.pqrs.Karabiner-Elements", source: .configFile)
    }

    private func skhd() -> HotkeyBinding {
        binding(owner: "skhd", source: .configFile)
    }

    private func alfred() -> HotkeyBinding {
        binding(owner: "Alfred", bundleID: "com.runningwithcrayons.Alfred", source: .configFile)
    }

    private func spotlight() -> HotkeyBinding {
        binding(owner: "macOS", bundleID: "com.apple.systempreferences", source: .systemShortcut)
    }

    // MARK: - Clear winners

    @Test("The lowest layer wins outright when it stands alone")
    func lowestLayerWins() throws {
        let driver = karabiner()
        let verdict = try #require(LikelyWinner.evaluate([spotlight(), alfred(), driver]))

        guard case .likely(let winner, let layer) = verdict else {
            Issue.record("Expected a clear winner, got \(String(describing: verdict))")
            return
        }
        #expect(winner.ownerName == "Karabiner-Elements")
        #expect(layer == .driver)
        #expect(verdict.winningBindingID == driver.id)
    }

    @Test("A system shortcut beats a global hotkey")
    func systemBeatsGlobalHotKey() throws {
        let verdict = try #require(LikelyWinner.evaluate([alfred(), spotlight()]))

        guard case .likely(let winner, let layer) = verdict else {
            Issue.record("Expected a clear winner, got \(String(describing: verdict))")
            return
        }
        #expect(winner.ownerName == "macOS")
        #expect(layer == .system)
    }

    @Test("An event tap beats a system shortcut")
    func eventTapBeatsSystem() throws {
        let verdict = try #require(LikelyWinner.evaluate([spotlight(), skhd()]))

        guard case .likely(let winner, _) = verdict else {
            Issue.record("Expected a clear winner, got \(String(describing: verdict))")
            return
        }
        #expect(winner.ownerName == "skhd")
    }

    @Test("A global shortcut beats an app menu item")
    func globalBeatsMenuItem() throws {
        let safari = binding(owner: "Safari", bundleID: "com.apple.Safari", source: .menuBar)
        let verdict = try #require(LikelyWinner.evaluate([safari, alfred()]))

        guard case .likely(let winner, _) = verdict else {
            Issue.record("Expected a clear winner, got \(String(describing: verdict))")
            return
        }
        #expect(winner.ownerName == "Alfred")
    }

    // MARK: - Declining to answer

    @Test("Two tools on the same layer stay a tie")
    func sameLayerTies() throws {
        let btt = binding(owner: "BetterTouchTool", bundleID: "com.hegenberg.BetterTouchTool", source: .configFile)
        let verdict = try #require(LikelyWinner.evaluate([skhd(), btt]))

        guard case .tied(let contenders, let layer) = verdict else {
            Issue.record("Expected a tie, got \(String(describing: verdict))")
            return
        }
        #expect(layer == .eventTap)
        #expect(Set(contenders.map(\.ownerName)) == ["skhd", "BetterTouchTool"])
        #expect(verdict.winningBindingID == nil)
    }

    @Test("A tie names only the contenders, not the losers")
    func tieExcludesHigherLayers() throws {
        let btt = binding(owner: "BetterTouchTool", bundleID: "com.hegenberg.BetterTouchTool", source: .configFile)
        let verdict = try #require(LikelyWinner.evaluate([skhd(), btt, spotlight(), alfred()]))

        guard case .tied(let contenders, _) = verdict else {
            Issue.record("Expected a tie, got \(String(describing: verdict))")
            return
        }
        #expect(contenders.count == 2)
        #expect(contenders.contains { $0.ownerName == "macOS" } == false)
    }

    @Test("Menu shortcuts alone are focus dependent, not a contest")
    func menuOnlyIsFocusDependent() {
        let safari = binding(owner: "Safari", bundleID: "com.apple.Safari", source: .menuBar)
        let notes = binding(owner: "Notes", bundleID: "com.apple.Notes", source: .menuBar)

        #expect(LikelyWinner.evaluate([safari, notes]) == LikelyWinner.focusDependent)
    }

    @Test("No bindings means no verdict")
    func emptyIsNil() {
        #expect(LikelyWinner.evaluate([]) == nil)
    }

    // MARK: - Copy

    @Test("Every verdict produces a summary free of em dashes")
    func summaryConventions() throws {
        let verdicts = [
            LikelyWinner.evaluate([spotlight(), alfred()]),
            LikelyWinner.evaluate([skhd(), binding(owner: "BetterTouchTool", bundleID: "com.hegenberg.BetterTouchTool", source: .configFile)]),
            LikelyWinner.evaluate([
                binding(owner: "Safari", bundleID: "com.apple.Safari", source: .menuBar),
                binding(owner: "Notes", bundleID: "com.apple.Notes", source: .menuBar),
            ]),
        ]

        for verdict in verdicts {
            let summary = try #require(verdict).summary
            #expect(summary.isEmpty == false)
            #expect(summary.contains("\u{2014}") == false, "Summary has an em dash: \(summary)")
        }
    }

    @Test("A three way tie lists every contender")
    func threeWayTieCopy() throws {
        let btt = binding(owner: "BetterTouchTool", bundleID: "com.hegenberg.BetterTouchTool", source: .configFile)
        let km = binding(owner: "Keyboard Maestro", bundleID: "com.stairways.keyboardmaestro.engine", source: .configFile)
        let verdict = try #require(LikelyWinner.evaluate([skhd(), btt, km]))

        let summary = verdict.summary
        #expect(summary.contains("skhd"))
        #expect(summary.contains("BetterTouchTool"))
        #expect(summary.contains("and Keyboard Maestro"))
    }
}
