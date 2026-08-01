import Foundation

/// Where in the macOS keyboard event stack a binding is hooked.
///
/// A keypress travels up a fairly well documented stack, and the first layer
/// that claims it usually swallows it before anything above ever sees it.
/// Karabiner rewrites the event inside a virtual keyboard driver, so it acts
/// first; CGEvent taps get the next look; then the system's own symbolic
/// hotkeys; then Carbon global hotkeys; and last of all the frontmost app's
/// menu. That ordering is the entire basis for the likely-winner hint.
///
/// It is a heuristic, not a promise. Two tools on the same layer are decided by
/// registration order, which no config file on disk records. Watching a real
/// keypress is the only way to be certain, and that is what the planned live
/// test mode is for.
///
/// Ordering is by raw value: lower means earlier in the stack, which means more
/// likely to win.
nonisolated enum HotkeyLayer: Int, CaseIterable, Comparable, Sendable {
    /// Karabiner-Elements. Remaps in a virtual HID driver, below the OS.
    case driver = 0
    /// CGEvent tap (skhd, BetterTouchTool, the Keyboard Maestro engine).
    case eventTap = 1
    /// A macOS symbolic hotkey.
    case system = 2
    /// Carbon `RegisterEventHotKey` (Hammerspoon, Alfred, HotkeyClash itself).
    case globalHotKey = 3
    /// An always-on tool whose hook point we do not recognise.
    case otherGlobal = 4
    /// An app menu item. Only live while that app is frontmost.
    case menuItem = 5

    static func < (lhs: HotkeyLayer, rhs: HotkeyLayer) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    // MARK: - Classification

    /// Maps a binding to its layer.
    ///
    /// Config-file bindings are the interesting case: the `.configFile` source
    /// lumps six very different tools together, so we look at who owns the
    /// binding. Bundle ID where there is one, owner name for skhd, which is a
    /// bare daemon with no bundle.
    static func classify(_ binding: HotkeyBinding) -> HotkeyLayer {
        switch binding.source {
        case .systemShortcut: .system
        case .menuBar: .menuItem
        case .configFile: configFileLayer(for: binding)
        }
    }

    private static func configFileLayer(for binding: HotkeyBinding) -> HotkeyLayer {
        switch binding.ownerBundleID ?? binding.ownerName {
        case "org.pqrs.Karabiner-Elements":
            .driver
        case "skhd", "com.hegenberg.BetterTouchTool", "com.stairways.keyboardmaestro.engine":
            .eventTap
        case "org.hammerspoon.Hammerspoon", "com.runningwithcrayons.Alfred":
            .globalHotKey
        default:
            .otherGlobal
        }
    }

    // MARK: - Display

    /// Short badge text for the detail pane.
    var label: String {
        switch self {
        case .driver: "Driver"
        case .eventTap: "Event Tap"
        case .system: "System"
        case .globalHotKey: "Global Hotkey"
        case .otherGlobal: "Global"
        case .menuItem: "Menu Item"
        }
    }

    /// One sentence on why this layer sits where it does. Shown as the reasoning
    /// behind the winner hint, so it has to make sense on its own.
    var explanation: String {
        switch self {
        case .driver:
            "Remapped in a virtual keyboard driver, before macOS or any app sees the event."
        case .eventTap:
            "Hooked by a CGEvent tap, which sees the key ahead of the system's own shortcuts and can swallow it."
        case .system:
            "A macOS system shortcut. It beats app level hotkeys, but an event tap can take the key first."
        case .globalHotKey:
            "A global hotkey registered with Carbon. It fires system wide, but only if nothing lower in the stack claimed the key."
        case .otherGlobal:
            "An always-on global shortcut. HotkeyClash does not know which layer this tool hooks, so its position here is a guess."
        case .menuItem:
            "An app menu shortcut. It fires only when that app is frontmost and nothing global claimed the key."
        }
    }
}
