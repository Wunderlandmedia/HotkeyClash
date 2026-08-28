import AppKit

/// What HotkeyClash actually saw when the user pressed a shortcut during a test.
///
/// Deliberately observations only, with no interpretation attached. Working out
/// what they mean belongs to `ShortcutTestVerdict`, which keeps the reasoning
/// pure and testable and leaves this type as a plain record of what the event
/// taps and the workspace reported.
nonisolated struct ShortcutTestResult: Equatable {

    /// How far up the event stack the keypress got before something claimed it.
    ///
    /// HotkeyClash listens twice: once at the head of the event tap chain, ahead
    /// of every other tap, and once at the tail, behind them all. A key that
    /// arrives at the head and never reaches the tail was eaten in between, and
    /// the only things living in between are other apps' event taps. That is the
    /// one piece of hard evidence this whole feature rests on.
    enum TapOutcome: Equatable {
        /// Seen at the head, never at the tail. Another app's event tap took it.
        case swallowedByEventTap
        /// Seen at both ends, so no event tap took it. What happens after that
        /// (a system shortcut, a Carbon global hotkey, the focused app's menu) is
        /// not something a tap can watch.
        case survivedTapLayer
    }

    /// A running app cut down to the two fields the verdict needs. Keeping
    /// `NSRunningApplication` out of the value type is what lets tests build
    /// results by hand.
    struct App: Equatable {
        let name: String
        let bundleID: String?
    }

    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    let tapOutcome: TapOutcome

    /// An app that came to the front just after the keypress, if any. The most
    /// telling signal available from outside: launchers and window managers
    /// nearly always show themselves the moment their hotkey fires.
    let activatedApp: App?

    /// Who was frontmost at the moment of the press. Needed to reason about menu
    /// shortcuts, which only ever fire for the app already in front.
    let frontmostApp: App?

    /// Device flags stripped, so an observed press compares cleanly against the
    /// combo under test.
    var normalizedModifiers: NSEvent.ModifierFlags {
        modifiers.intersection([.command, .option, .shift, .control])
    }

    /// Main actor only, because `ShortcutFormatter` is. Everything else here is
    /// free to cross actors, which is what the taps need.
    @MainActor
    var displayString: String {
        ShortcutFormatter.displayString(
            keyCode: UInt32(keyCode),
            carbonModifiers: ShortcutFormatter.carbonModifiers(from: modifiers)
        )
    }
}
