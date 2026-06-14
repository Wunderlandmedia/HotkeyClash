import SwiftUI

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

            Divider()

            // Binding list
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sortedBindings) { binding in
                    HStack(spacing: 10) {
                        appIcon(for: binding)
                            .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(binding.ownerName)
                                .font(.subheadline.weight(.semibold))

                            Text(binding.action)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        sourceBadge(for: binding.source)
                    }
                    .padding(.vertical, 8)

                    if binding.id != sortedBindings.last?.id {
                        Divider()
                            .padding(.leading, 38)
                    }
                }
            }

            Divider()

            // Explanation
            Text("Global and system shortcuts take priority over app menu shortcuts. Menu shortcuts only apply when that app is focused.")
                .font(.caption)
                .foregroundStyle(.tertiary)
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

    private var sortedBindings: [HotkeyBinding] {
        conflict.bindings.sorted { lhs, rhs in
            let order: [HotkeyBinding.BindingSource] = [.systemShortcut, .configFile, .menuBar]
            let lhsIndex = order.firstIndex(of: lhs.source) ?? 3
            let rhsIndex = order.firstIndex(of: rhs.source) ?? 3
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
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

    @ViewBuilder
    private func appIcon(for binding: HotkeyBinding) -> some View {
        if let bundleID = binding.ownerBundleID, let icon = icons[bundleID] {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: iconName(for: binding.source))
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func iconName(for source: HotkeyBinding.BindingSource) -> String {
        switch source {
        case .menuBar: "menubar.rectangle"
        case .configFile: "doc.text"
        case .systemShortcut: "gearshape"
        }
    }

    // MARK: - Source Badge

    private func sourceBadge(for source: HotkeyBinding.BindingSource) -> some View {
        Text(sourceLabel(for: source))
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(sourceColor(for: source))
            .background(sourceColor(for: source).opacity(0.12), in: Capsule())
    }

    private func sourceLabel(for source: HotkeyBinding.BindingSource) -> String {
        switch source {
        case .menuBar: "Menu Bar"
        case .configFile: "Config"
        case .systemShortcut: "System"
        }
    }

    private func sourceColor(for source: HotkeyBinding.BindingSource) -> Color {
        switch source {
        case .menuBar: .blue
        case .configFile: .purple
        case .systemShortcut: .orange
        }
    }
}
