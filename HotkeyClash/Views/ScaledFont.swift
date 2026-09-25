import AppKit
import SwiftUI

extension EnvironmentValues {
    /// The panel's text multiplier, from `PanelTextSize`. Set once at the root of
    /// the panel and read by every `scaledFont` below it.
    @Entry var panelTextScale: CGFloat = 1
}

/// A font that honours the panel's text size.
///
/// `.font(.callout)` is a fixed 12 points on macOS no matter what, so the panel
/// cannot use the text styles directly. This looks up what the style would have
/// been and multiplies it by the scale in the environment, which keeps the
/// familiar style names at the call sites while letting the whole panel grow.
struct ScaledFont: ViewModifier {
    @Environment(\.panelTextScale) private var scale

    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: (size * scale).rounded(), weight: weight, design: design))
    }

    /// The point size macOS uses for a text style, asked of AppKit rather than
    /// hard-coded so we stay in step if Apple ever changes them.
    static func pointSize(for style: Font.TextStyle) -> CGFloat {
        NSFont.preferredFont(forTextStyle: nsTextStyle(for: style)).pointSize
    }

    private static func nsTextStyle(for style: Font.TextStyle) -> NSFont.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}

extension View {
    /// A text style scaled by the panel's text size. Headline keeps its bold,
    /// which the system style carries implicitly and a sized font would drop.
    func scaledFont(_ style: Font.TextStyle, weight: Font.Weight? = nil, design: Font.Design = .default) -> some View {
        modifier(ScaledFont(
            size: ScaledFont.pointSize(for: style),
            weight: weight ?? (style == .headline ? .bold : .regular),
            design: design
        ))
    }

    /// A fixed point size scaled by the panel's text size, for the SF Symbols
    /// that were sized by hand rather than by style.
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: .default))
    }
}
