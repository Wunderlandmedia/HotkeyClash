import AppKit
import Testing
@testable import HotkeyClash

/// Tests for the live-test verdict. The point of this feature is that it watched
/// the key rather than guessing at it, so the cases that matter most are the ones
/// where the observation is thin: it has to stay honest about what it did not see
/// instead of rounding up to a winner.
@Suite("Shortcut test verdict")
@MainActor
struct ShortcutTestVerdictTests {

    // MARK: - Helpers

    /// Cmd+Space throughout, which is the combo everyone actually fights over.
    private static let keyCode: UInt16 = 0x31
    private static let modifiers: NSEvent.ModifierFlags = [.command]

    private func binding(
        owner: String,
        bundleID: String? = nil,
        source: HotkeyBinding.BindingSource
    ) -> HotkeyBinding {
        HotkeyBinding(
            keyCode: Self.keyCode,
            modifiers: Self.modifiers,
            ownerName: owner,
            ownerBundleID: bundleID,
            action: "Action",
            source: source
        )
    }

    private func skhd() -> HotkeyBinding {
        binding(owner: "skhd", source: .configFile)
    }

    private func betterTouchTool() -> HotkeyBinding {
        binding(owner: "BetterTouchTool", bundleID: "com.hegenberg.BetterTouchTool", source: .configFile)
    }

    private func alfred() -> HotkeyBinding {
        binding(owner: "Alfred", bundleID: "com.runningwithcrayons.Alfred", source: .configFile)
    }

    private func spotlight() -> HotkeyBinding {
        binding(owner: "macOS", bundleID: "com.apple.systempreferences", source: .systemShortcut)
    }

    private func result(
        keyCode: UInt16 = ShortcutTestVerdictTests.keyCode,
        modifiers: NSEvent.ModifierFlags = ShortcutTestVerdictTests.modifiers,
        outcome: ShortcutTestResult.TapOutcome,
        activated: ShortcutTestResult.App? = nil,
        frontmost: ShortcutTestResult.App? = nil
    ) -> ShortcutTestResult {
        ShortcutTestResult(
            keyCode: keyCode,
            modifiers: modifiers,
            tapOutcome: outcome,
            activatedApp: activated,
            frontmostApp: frontmost
        )
    }

    private func evaluate(
        _ result: ShortcutTestResult?,
        bindings: [HotkeyBinding]
    ) -> ShortcutTestVerdict {
        ShortcutTestVerdict.evaluate(
            result: result,
            bindings: bindings,
            expectedKeyCode: Self.keyCode,
            expectedModifiers: Self.modifiers
        )
    }

    // MARK: - The event tap layer

    @Test("A key that never reaches the tail was taken by an event tap")
    func swallowedNamesTheOnlyTapTool() {
        let verdict = evaluate(
            result(outcome: .swallowedByEventTap),
            bindings: [skhd(), alfred(), spotlight()]
        )

        #expect(verdict == .swallowedByTap(candidates: ["skhd"]))
        #expect(verdict.tone == .confirmed)
        #expect(verdict.headline == "skhd took the key")
    }

    @Test("Two tap tools on the combo stay unresolved")
    func swallowedWithSeveralCandidates() {
        let verdict = evaluate(
            result(outcome: .swallowedByEventTap),
            bindings: [skhd(), betterTouchTool()]
        )

        guard case .swallowedByTap(let candidates) = verdict else {
            Issue.record("Expected an event tap verdict, got \(verdict)")
            return
        }
        #expect(candidates == ["skhd", "BetterTouchTool"])
        #expect(verdict.tone == .informative)
        #expect(verdict.summary.contains("skhd and BetterTouchTool"))
    }

    @Test("A tap took it and the scan has no idea which tool that was")
    func swallowedBySomethingUnscanned() {
        let verdict = evaluate(
            result(outcome: .swallowedByEventTap),
            bindings: [alfred(), spotlight()]
        )

        #expect(verdict == .swallowedByTap(candidates: []))
        #expect(verdict.summary.contains("cannot read the config of"))
    }

    // MARK: - Above the tap layer

    @Test("An app that jumps to the front and claims the combo is the winner")
    func activationConfirmsAWinner() {
        let launcher = alfred()
        let verdict = evaluate(
            result(
                outcome: .survivedTapLayer,
                activated: .init(name: "Alfred", bundleID: "com.runningwithcrayons.Alfred")
            ),
            bindings: [launcher, spotlight()]
        )

        #expect(verdict == .reachedApp(binding: launcher, evidence: .cameToFront))
        #expect(verdict.confirmedBindingID == launcher.id)
        #expect(verdict.tone == .confirmed)
    }

    @Test("An app with no bundle ID still matches on its name")
    func activationMatchesOnNameWhenThereIsNoBundleID() {
        let daemon = skhd()
        let verdict = evaluate(
            result(
                outcome: .survivedTapLayer,
                activated: .init(name: "skhd", bundleID: nil)
            ),
            bindings: [daemon]
        )

        #expect(verdict.confirmedBindingID == daemon.id)
    }

    @Test("When an app claims a combo twice, the earlier layer is credited")
    func activationPrefersTheLowerLayer() {
        let global = alfred()
        let menu = binding(owner: "Alfred", bundleID: "com.runningwithcrayons.Alfred", source: .menuBar)
        let verdict = evaluate(
            result(
                outcome: .survivedTapLayer,
                activated: .init(name: "Alfred", bundleID: "com.runningwithcrayons.Alfred")
            ),
            bindings: [menu, global]
        )

        #expect(verdict.confirmedBindingID == global.id)
    }

    @Test("An app that reacts without a registration on file is reported as such")
    func activationWithoutARegistration() {
        let verdict = evaluate(
            result(
                outcome: .survivedTapLayer,
                activated: .init(name: "Raycast", bundleID: "com.raycast.macos")
            ),
            bindings: [spotlight()]
        )

        #expect(verdict == .unregisteredApp(name: "Raycast"))
        #expect(verdict.confirmedBindingID == nil)
    }

    @Test("The frontmost app's menu shortcut is credited, but only hedged")
    func frontmostMenuItemIsTheFallback() {
        let safari = binding(owner: "Safari", bundleID: "com.apple.Safari", source: .menuBar)
        let verdict = evaluate(
            result(
                outcome: .survivedTapLayer,
                frontmost: .init(name: "Safari", bundleID: "com.apple.Safari")
            ),
            bindings: [safari, alfred()]
        )

        #expect(verdict == .reachedApp(binding: safari, evidence: .alreadyFrontmost))
        #expect(verdict.tone == .informative)
        #expect(verdict.summary.contains("could also have taken the key silently"))
    }

    @Test("A global hotkey firing invisibly leaves no winner, only an exclusion")
    func survivedWithNothingToSee() {
        let verdict = evaluate(
            result(
                outcome: .survivedTapLayer,
                frontmost: .init(name: "Safari", bundleID: "com.apple.Safari")
            ),
            bindings: [skhd(), alfred(), spotlight()]
        )

        #expect(verdict == .survivedUnclaimed(ruledOut: ["skhd"]))
        #expect(verdict.tone == .inconclusive)
        #expect(verdict.confirmedBindingID == nil)
        #expect(verdict.summary.contains("skhd did not take it"))
    }

    @Test("With no tap tools involved there is nothing to rule out either")
    func survivedWithNothingRuledOut() {
        let verdict = evaluate(
            result(outcome: .survivedTapLayer),
            bindings: [alfred(), spotlight()]
        )

        #expect(verdict == .survivedUnclaimed(ruledOut: []))
        #expect(verdict.summary.contains("did not take it") == false)
    }

    // MARK: - Refusing to answer

    @Test("A different key arriving means something rewrote it first")
    func rewrittenKeyIsReportedAsARemap() {
        let karabiner = binding(owner: "Karabiner-Elements", bundleID: "org.pqrs.Karabiner-Elements", source: .configFile)
        let verdict = evaluate(
            result(keyCode: 0x0C, outcome: .survivedTapLayer), // Cmd+Q instead of Cmd+Space
            bindings: [karabiner, alfred()]
        )

        guard case .rewritten(_, _, let driverName) = verdict else {
            Issue.record("Expected a rewritten verdict, got \(verdict)")
            return
        }
        #expect(driverName == "Karabiner-Elements")
        #expect(verdict.summary.contains("exactly what Karabiner-Elements does"))
    }

    @Test("A rewrite with no driver in the scan names the usual suspect generically")
    func rewrittenWithNoKnownDriver() {
        let verdict = evaluate(
            result(modifiers: [.command, .shift], outcome: .survivedTapLayer),
            bindings: [alfred()]
        )

        guard case .rewritten(_, _, let driverName) = verdict else {
            Issue.record("Expected a rewritten verdict, got \(verdict)")
            return
        }
        #expect(driverName == nil)
        #expect(verdict.summary.contains("like Karabiner-Elements"))
    }

    @Test("Device flags on the observed press are not treated as a rewrite")
    func capsLockDoesNotLookLikeARemap() {
        let verdict = evaluate(
            result(modifiers: [.command, .capsLock], outcome: .swallowedByEventTap),
            bindings: [skhd()]
        )

        #expect(verdict == .swallowedByTap(candidates: ["skhd"]))
    }

    @Test("A window that closes with no keypress admits it saw nothing")
    func timeoutSaysSo() {
        let verdict = evaluate(nil, bindings: [skhd(), alfred()])

        #expect(verdict == .nothingSeen)
        #expect(verdict.tone == .inconclusive)
        #expect(verdict.confirmedBindingID == nil)
    }

    // MARK: - Copy

    @Test("Every verdict has copy, and none of it uses em dashes")
    func copyConventions() {
        let verdicts: [ShortcutTestVerdict] = [
            .swallowedByTap(candidates: ["skhd"]),
            .swallowedByTap(candidates: ["skhd", "BetterTouchTool"]),
            .swallowedByTap(candidates: []),
            .reachedApp(binding: alfred(), evidence: .cameToFront),
            .reachedApp(binding: alfred(), evidence: .alreadyFrontmost),
            .unregisteredApp(name: "Raycast"),
            .survivedUnclaimed(ruledOut: ["skhd"]),
            .survivedUnclaimed(ruledOut: []),
            .rewritten(expected: "\u{2318}Space", observed: "\u{2318}Q", driverName: nil),
            .nothingSeen,
        ]

        for verdict in verdicts {
            #expect(verdict.headline.isEmpty == false)
            #expect(verdict.summary.isEmpty == false)
            #expect(verdict.headline.contains("\u{2014}") == false, "Em dash in: \(verdict.headline)")
            #expect(verdict.summary.contains("\u{2014}") == false, "Em dash in: \(verdict.summary)")
        }
    }

    @Test("A three way tap tie lists every candidate")
    func threeWayCandidateCopy() {
        let km = binding(owner: "Keyboard Maestro", bundleID: "com.stairways.keyboardmaestro.engine", source: .configFile)
        let verdict = evaluate(
            result(outcome: .swallowedByEventTap),
            bindings: [skhd(), betterTouchTool(), km]
        )

        #expect(verdict.summary.contains("skhd, BetterTouchTool, and Keyboard Maestro"))
    }
}
