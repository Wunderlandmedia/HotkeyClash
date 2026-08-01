import SwiftUI

/// One binding inside a conflict's detail pane: who owns it, what it does,
/// where in the event stack it hooks, and whether it is our pick to win.
///
/// Pulled out of `ConflictDetailView` when the layer badge arrived; the row had
/// grown enough opinions of its own to deserve a file.
struct BindingRow: View {
    let binding: HotkeyBinding
    let icon: NSImage?
    /// True when the likely-winner verdict named this binding outright.
    let isLikelyWinner: Bool

    private var layer: HotkeyLayer { HotkeyLayer.classify(binding) }

    var body: some View {
        HStack(spacing: 10) {
            appIcon
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(binding.ownerName)
                        .font(.subheadline.weight(.semibold))

                    if isLikelyWinner {
                        Label("Likely winner", systemImage: "checkmark.seal.fill")
                            .labelStyle(.iconOnly)
                            .font(.caption)
                            .foregroundStyle(.green)
                            .help("Most likely to receive this key")
                    }
                }

                Text(binding.action)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            badge(layer.label, tint: layerColor)
                .help(layer.explanation)
            badge(sourceLabel, tint: sourceColor)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Icon

    @ViewBuilder
    private var appIcon: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: fallbackIconName)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var fallbackIconName: String {
        switch binding.source {
        case .menuBar: "menubar.rectangle"
        case .configFile: "doc.text"
        case .systemShortcut: "gearshape"
        }
    }

    // MARK: - Badges

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
    }

    /// Deliberately desaturated next to the source badge. The layer is the
    /// nuance; the source is still the headline.
    private var layerColor: Color {
        switch layer {
        case .driver, .eventTap: .pink
        case .system, .globalHotKey, .otherGlobal: .teal
        case .menuItem: .secondary
        }
    }

    private var sourceLabel: String {
        switch binding.source {
        case .menuBar: "Menu Bar"
        case .configFile: "Config"
        case .systemShortcut: "System"
        }
    }

    private var sourceColor: Color {
        switch binding.source {
        case .menuBar: .blue
        case .configFile: .purple
        case .systemShortcut: .orange
        }
    }
}
