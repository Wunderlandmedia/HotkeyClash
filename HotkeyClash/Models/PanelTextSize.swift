import CoreGraphics

/// How large the results panel draws its text, chosen in Settings or with
/// Cmd+Plus and Cmd+Minus while the panel is open.
///
/// This exists because macOS gives us nothing to lean on. SwiftUI accepts
/// `.dynamicTypeSize` on the Mac and then ignores it, the text styles are fixed
/// point sizes, and the system Text Size setting only reaches the apps Apple
/// wired into it. People on large high resolution displays were left squinting
/// at 10 point type with no way to fix it short of making every other app huge.
/// So the panel carries its own scale.
enum PanelTextSize: Int, CaseIterable, Identifiable {
    case standard
    case large
    case larger
    case largest

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .standard: "Default"
        case .large: "Large"
        case .larger: "Larger"
        case .largest: "Largest"
        }
    }

    /// Multiplier applied to every font in the panel. The steps are even enough
    /// that each press of Cmd+Plus is a visible change, and the top one stops
    /// short of the point where the sidebar can only fit a few rows.
    var scale: CGFloat {
        switch self {
        case .standard: 1.0
        case .large: 1.15
        case .larger: 1.3
        case .largest: 1.5
        }
    }

    /// One step up, or nil at the top. Nil rather than clamping so the key
    /// handler can tell "nothing to do" apart from "done".
    var stepUp: PanelTextSize? { PanelTextSize(rawValue: rawValue + 1) }

    /// One step down, or nil at the bottom.
    var stepDown: PanelTextSize? { PanelTextSize(rawValue: rawValue - 1) }

    // MARK: - Layout

    /// The panel size at the default text size.
    static let basePanelSize = CGSize(width: 880, height: 620)

    /// The sidebar width at the default text size. Wide enough for a four
    /// modifier combo badge next to "Keyboard Maestro vs Hammerspoon".
    static let baseSidebarWidth: CGFloat = 320

    /// The sidebar grows with the text, or larger sizes would just truncate
    /// every row and nobody would be better off.
    var sidebarWidth: CGFloat { (Self.baseSidebarWidth * scale).rounded() }

    /// The panel size for this text size, never larger than the space it has
    /// to fit in. Largest on a 13 inch display would otherwise open with its
    /// bottom edge under the Dock; clamped, the list and the detail pane scroll.
    func panelSize(fitting available: CGSize) -> CGSize {
        CGSize(
            width: min((Self.basePanelSize.width * scale).rounded(), available.width),
            height: min((Self.basePanelSize.height * scale).rounded(), available.height)
        )
    }
}
