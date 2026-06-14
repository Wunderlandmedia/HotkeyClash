import SwiftUI

struct ConflictRow: View {
    let conflict: Conflict

    var body: some View {
        HStack(spacing: 8) {
            Text(conflict.displayString)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))

            Text(clashDescription)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            // Shape differs by severity so it reads without relying on color alone.
            Image(systemName: conflict.severity.symbolName)
                .font(.system(size: 9))
                .foregroundStyle(conflict.severity.tint)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(conflict.displayString), \(conflict.severity.accessibilityDescription), \(clashDescription)")
    }

    private var clashDescription: String {
        let unique = Set(conflict.bindings.map(\.ownerName))
        if unique.count == 2 {
            let sorted = unique.sorted()
            return "\(sorted[0]) vs \(sorted[1])"
        }
        return "\(unique.count) apps"
    }
}

extension Conflict.Severity {
    /// Accent color. Centralized so the sidebar and detail pane never disagree.
    var tint: Color {
        switch self {
        case .definite: .red
        case .potential: .orange
        }
    }

    /// SF Symbol whose shape (not just color) distinguishes the severity.
    var symbolName: String {
        switch self {
        case .definite: "exclamationmark.circle.fill"
        case .potential: "circle.fill"
        }
    }

    /// Spoken description for VoiceOver.
    var accessibilityDescription: String {
        switch self {
        case .definite: "definite conflict"
        case .potential: "potential conflict"
        }
    }
}
