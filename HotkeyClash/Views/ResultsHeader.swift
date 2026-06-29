import SwiftUI

/// The summary bar above the results: a one-glance verdict on the left, and the
/// Export / Rescan actions on the right.
///
/// The headline intentionally leads with *real* conflicts (the ones that actually
/// bite), and tucks the menu-overlap noise into the subhead. Most of those
/// overlaps are just every app sharing Cmd+C, so they shouldn't steal the spotlight.
struct ResultsHeader: View {
    let realConflictCount: Int
    let appOverlapCount: Int
    let bindingCount: Int
    let scanDuration: TimeInterval
    let onRescan: () -> Void
    let onExport: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Green check when there's nothing to worry about, orange warning when
            // there is. Color plus shape so it reads without relying on color alone.
            Image(systemName: realConflictCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(realConflictCount > 0 ? .orange : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.subheadline.weight(.semibold))
                Text(subhead)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Export", systemImage: "square.and.arrow.up", action: onExport)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Export the conflict list as a Markdown file")
            Button("Rescan", action: onRescan)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var headline: String {
        guard realConflictCount > 0 else { return "No always-on conflicts" }
        let noun = realConflictCount == 1 ? "real conflict" : "real conflicts"
        return "\(realConflictCount) \(noun)"
    }

    private var subhead: String {
        let overlaps = appOverlapCount == 1 ? "1 menu overlap" : "\(appOverlapCount) menu overlaps"
        return "\(overlaps), only clash when an app is focused \u{00B7} scanned \(bindingCount) shortcuts in \(String(format: "%.1f", scanDuration))s"
    }
}
