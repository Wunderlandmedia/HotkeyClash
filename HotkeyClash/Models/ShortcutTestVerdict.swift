import AppKit

/// What a live shortcut test proved, in plain language.
///
/// `LikelyWinner` reasons from config files and guesses. This reasons from a real
/// keypress, so where the two disagree, this one is the more trustworthy of the
/// pair. It still has blind spots and names them: once a key gets past the event
/// tap layer, a macOS system shortcut or a Carbon global hotkey can swallow it
/// without leaving anything an outside observer could ever see. Saying so is the
/// whole point. A confident wrong answer here would be worse than the guess it
/// was meant to replace.
nonisolated enum ShortcutTestVerdict: Equatable {

    /// How we know an app got the key. Coming to the front is strong evidence;
    /// already being in front is circumstantial, and the copy says so.
    enum Evidence: Equatable {
        case cameToFront
        case alreadyFrontmost
    }

    /// Drives the tint and icon. Confirmed means we watched it happen, informative
    /// means we learned something real but short of proof, inconclusive means the
    /// key vanished somewhere no observer can follow.
    enum Tone: Equatable {
        case confirmed
        case informative
        case inconclusive
    }

    /// An event tap consumed the key. Candidates are the tools from the last scan
    /// that hook that layer with this combo, which may be one, several, or none.
    case swallowedByTap(candidates: [String])
    /// An app that claims this combo appears to have received it.
    case reachedApp(binding: HotkeyBinding, evidence: Evidence)
    /// An app clearly reacted, but the scan has no record of it claiming this combo.
    case unregisteredApp(name: String)
    /// The key survived every event tap and nothing visible happened afterwards.
    case survivedUnclaimed(ruledOut: [String])
    /// What reached macOS was not the combo under test, so something rewrote it
    /// below the OS.
    case rewritten(expected: String, observed: String, driverName: String?)
    /// The listen window closed without a single keypress arriving.
    case nothingSeen

    // MARK: - Evaluation

    /// Turns one observation into a verdict, read against what the scan already knew.
    ///
    /// Pass `nil` for `result` when the listen window timed out. Everything else
    /// here is value in, string out, which is why the copy can be unit tested.
    ///
    /// Main actor only for one reason: naming the combo that was expected means
    /// asking `ShortcutFormatter`, which is isolated. Nothing else in here cares.
    @MainActor
    static func evaluate(
        result: ShortcutTestResult?,
        bindings: [HotkeyBinding],
        expectedKeyCode: UInt16,
        expectedModifiers: NSEvent.ModifierFlags
    ) -> ShortcutTestVerdict {
        guard let result else { return .nothingSeen }

        let expected = expectedModifiers.intersection([.command, .option, .shift, .control])
        guard result.keyCode == expectedKeyCode, result.normalizedModifiers == expected else {
            return .rewritten(
                expected: display(keyCode: expectedKeyCode, modifiers: expected),
                observed: result.displayString,
                driverName: bindings.first { HotkeyLayer.classify($0) == .driver }?.ownerName
            )
        }

        let tapTools = uniqueNames(bindings.filter { HotkeyLayer.classify($0) == .eventTap })

        switch result.tapOutcome {
        case .swallowedByEventTap:
            return .swallowedByTap(candidates: tapTools)

        case .survivedTapLayer:
            if let activated = result.activatedApp {
                if let match = binding(in: bindings, matching: activated) {
                    return .reachedApp(binding: match, evidence: .cameToFront)
                }
                return .unregisteredApp(name: activated.name)
            }
            // Nothing came to the front. A menu shortcut would not make anything
            // appear, so the app that was already there is the next best candidate.
            if let front = result.frontmostApp,
               let match = bindings.first(where: { $0.source == .menuBar && matches($0, front) }) {
                return .reachedApp(binding: match, evidence: .alreadyFrontmost)
            }
            return .survivedUnclaimed(ruledOut: tapTools)
        }
    }

    // MARK: - Copy

    var headline: String {
        switch self {
        case .swallowedByTap(let candidates):
            candidates.count == 1 ? "\(candidates[0]) took the key" : "An event tap took the key"
        case .reachedApp(let binding, _):
            "\(binding.ownerName) got the key"
        case .unregisteredApp(let name):
            "\(name) took the key"
        case .survivedUnclaimed:
            "No visible winner"
        case .rewritten:
            "The key was rewritten first"
        case .nothingSeen:
            "Nothing reached the listener"
        }
    }

    var summary: String {
        switch self {
        case .swallowedByTap(let candidates):
            swallowedSummary(candidates: candidates)

        case .reachedApp(let binding, .cameToFront):
            "\(binding.ownerName) came to the front right after the press, and it does claim this combo. Nothing swallowed the key at the event tap layer, so this is as close to a confirmed answer as watching from outside can get."

        case .reachedApp(let binding, .alreadyFrontmost):
            "No event tap took the key and nothing came to the front. \(binding.ownerName) was already frontmost and has a menu shortcut on this combo, so it most likely fired. A macOS system shortcut could also have taken the key silently, which nothing outside the OS can see."

        case .unregisteredApp(let name):
            "\(name) came to the front right after the press, but nothing in the last scan records it claiming this combo. Either it registers the shortcut somewhere HotkeyClash cannot read, or it was on its way to the front for an unrelated reason."

        case .survivedUnclaimed(let ruledOut):
            unclaimedSummary(ruledOut: ruledOut)

        case .rewritten(let expected, let observed, let driverName):
            rewrittenSummary(expected: expected, observed: observed, driverName: driverName)

        case .nothingSeen:
            "HotkeyClash listened and no keypress arrived at all. If you did press the combination, something intercepted it below the event tap layer, which in practice means a keyboard driver remap. If you did not, run the test again."
        }
    }

    /// The binding the observation points at, when it points at exactly one. Used
    /// to mark the row in the list, so it stays nil for every hedged verdict.
    var confirmedBindingID: UUID? {
        if case .reachedApp(let binding, _) = self { return binding.id }
        return nil
    }

    var tone: Tone {
        switch self {
        case .swallowedByTap(let candidates):
            candidates.count == 1 ? .confirmed : .informative
        case .reachedApp(_, .cameToFront):
            .confirmed
        case .reachedApp(_, .alreadyFrontmost), .unregisteredApp, .rewritten:
            .informative
        case .survivedUnclaimed, .nothingSeen:
            .inconclusive
        }
    }

    var iconName: String {
        switch self {
        case .swallowedByTap: "bolt.horizontal.circle"
        case .reachedApp: "checkmark.seal"
        case .unregisteredApp: "questionmark.app"
        case .survivedUnclaimed: "eye.slash"
        case .rewritten: "arrow.triangle.swap"
        case .nothingSeen: "questionmark.circle"
        }
    }

    // MARK: - Copy helpers

    private func swallowedSummary(candidates: [String]) -> String {
        let observed = "The key reached HotkeyClash's first listener and never arrived at the second, so an event tap swallowed it on the way."
        switch candidates.count {
        case 0:
            return "\(observed) Nothing in the last scan claims this combo at that layer, so whatever took it is a tool HotkeyClash cannot read the config of."
        case 1:
            return "\(observed) \(candidates[0]) is the only tool in the scan that hooks that layer with this combo, so it is almost certainly holding the key."
        default:
            return "\(observed) \(Self.joined(candidates)) all hook that layer with this combo, and the tap chain does not record which of them acted."
        }
    }

    private func unclaimedSummary(ruledOut: [String]) -> String {
        var text = "The key got past every event tap, and nothing came to the front to give the winner away. From there a macOS system shortcut or a Carbon global hotkey can take a key without leaving a trace anything outside the OS can follow."
        if !ruledOut.isEmpty {
            text += " What this does settle is that \(Self.joined(ruledOut)) did not take it."
        }
        return text
    }

    private func rewrittenSummary(expected: String, observed: String, driverName: String?) -> String {
        var text = "You pressed something, and what reached macOS was \(observed) rather than \(expected). That means it was rewritten below the operating system"
        if let driverName {
            text += ", which is exactly what \(driverName) does."
        } else {
            text += ", which is what a virtual keyboard driver like Karabiner-Elements does."
        }
        text += " Worth pressing again to rule out a slip of the fingers before believing that."
        return text
    }

    // MARK: - Matching

    /// Bundle ID where both sides have one, name otherwise. Config-file bindings
    /// often have no bundle ID, so the name fallback earns its keep.
    private static func matches(_ binding: HotkeyBinding, _ app: ShortcutTestResult.App) -> Bool {
        if let bundleID = binding.ownerBundleID, let appBundleID = app.bundleID {
            return bundleID == appBundleID
        }
        return binding.ownerName == app.name
    }

    private static func binding(in bindings: [HotkeyBinding], matching app: ShortcutTestResult.App) -> HotkeyBinding? {
        // Prefer whichever candidate hooks the keyboard earliest: if an app both
        // registers a global hotkey and has a menu item on the same combo, the
        // global one is what made it appear.
        bindings
            .filter { matches($0, app) }
            .min { HotkeyLayer.classify($0) < HotkeyLayer.classify($1) }
    }

    private static func uniqueNames(_ bindings: [HotkeyBinding]) -> [String] {
        var seen: Set<String> = []
        return bindings.map(\.ownerName).filter { seen.insert($0).inserted }
    }

    @MainActor
    private static func display(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        ShortcutFormatter.displayString(
            keyCode: UInt32(keyCode),
            carbonModifiers: ShortcutFormatter.carbonModifiers(from: modifiers)
        )
    }

    private static func joined(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + ", and \(names[names.count - 1])"
        }
    }
}
