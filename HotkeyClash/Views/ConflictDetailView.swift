import SwiftUI

/// The full picture for one conflict: the combo, our guess at who wins it, and
/// every binding that claims it, ordered by how early it hooks the event stack.
struct ConflictDetailView: View {
    let conflict: Conflict
    @State private var icons: [String: NSImage] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Key combo header
            HStack(spacing: 12) {
                Text(conflict.displayString)
                    .font(.system(.title2, design: .monospaced).weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(conflict.bindings.count) apps use this shortcut")
                        .font(.subheadline.weight(.medium))

                    Text(severityLabel)
                        .font(.caption)
                        .foregroundStyle(conflict.severity.tint)
                }
            }

            if let verdict = conflict.likelyWinner {
                LikelyWinnerCallout(verdict: verdict)
            }

            Divider()

            // Binding list
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sortedBindings) { binding in
                    BindingRow(
                        binding: binding,
                        icon: binding.ownerBundleID.flatMap { icons[$0] },
                        isLikelyWinner: binding.id == winningBindingID
                    )

                    if binding.id != sortedBindings.last?.id {
                        Divider()
                            .padding(.leading, 38)
                    }
                }
            }

            Divider()

            // Explanation
            Text("Ordered by where each shortcut hooks the keyboard: driver remaps first, then event taps, system shortcuts, global hotkeys, and finally app menus. Registration order breaks ties, and nothing on disk records it.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: conflict.id) { loadIcons() }
    }

    private var severityLabel: String {
        switch conflict.severity {
        case .definite:
            "Definite conflict: multiple global shortcuts on the same key"
        case .potential:
            "Potential conflict: overlapping menu shortcuts across apps"
        }
    }

    private var winningBindingID: UUID? {
        conflict.likelyWinner?.winningBindingID
    }

    /// Sorted by event-stack layer so the list reads top-down in the same order
    /// macOS resolves the keypress, with apps alphabetical inside a layer.
    private var sortedBindings: [HotkeyBinding] {
        conflict.bindings.sorted { lhs, rhs in
            let lhsLayer = HotkeyLayer.classify(lhs)
            let rhsLayer = HotkeyLayer.classify(rhs)
            if lhsLayer != rhsLayer { return lhsLayer < rhsLayer }
            return lhs.ownerName < rhs.ownerName
        }
    }

    // MARK: - App Icon

    /// Resolves app icons once per conflict (in a `.task`) rather than hitting
    /// NSWorkspace on every render of every row.
    private func loadIcons() {
        var resolved: [String: NSImage] = [:]
        for bundleID in Set(conflict.bindings.compactMap(\.ownerBundleID)) {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                resolved[bundleID] = NSWorkspace.shared.icon(forFile: appURL.path(percentEncoded: false))
            }
        }
        icons = resolved
    }
}
