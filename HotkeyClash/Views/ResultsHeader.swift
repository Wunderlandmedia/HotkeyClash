import SwiftUI

/// The summary bar above the results: a one-glance verdict on the left, and the
/// Export / Rescan actions on the right.
///
/// The headline intentionally leads with *real* conflicts (the ones that actually
/// bite), and tucks the menu-overlap noise into the subhead. Most of those
/// overlaps are just every app sharing Cmd+C, so they shouldn't steal the spotlight.
struct ResultsHeader: View {
    @Binding var scope: ConflictScope
    let realConflictCount: Int
    let appOverlapCount: Int
    /// Real conflicts that weren't in the previous scan. Zero on the first scan and
    /// whenever a rescan surfaced nothing new; a capsule appears only when positive.
    let newConflictCount: Int
    let bindingCount: Int
    let scanDuration: TimeInterval
    let lastScanDate: Date?
    /// Whether the panel stays put when the user clicks into another app.
    @Binding var isPinned: Bool
    let onRescan: () -> Void
    let onExport: () -> Void

    /// Drives the "2m ago" text. Held here rather than read inline so the label
    /// keeps counting up while the panel sits open, instead of freezing at
    /// whatever it said when the view was built.
    @State private var now = Date()

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
            if newConflictCount > 0 {
                newBadge
            }
            Spacer()
            Picker("Show", selection: $scope) {
                ForEach(ConflictScope.allCases) { scope in
                    Text(scope.label).tag(scope)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help("Choose which conflicts the list shows")
            Toggle(isOn: $isPinned) {
                Label("Keep panel open", systemImage: isPinned ? "pin.fill" : "pin")
                    .labelStyle(.iconOnly)
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help(isPinned
                  ? "Panel stays open until you press Escape or click the menu bar icon"
                  : "Keep the panel open when you click into another app")
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
        .task {
            // A slow heartbeat, and only while this header is on screen. The panel
            // is usually open for a few seconds, so this costs almost nothing.
            while !Task.isCancelled {
                try? await Task.sleep(for: ScanTimeFormatter.refreshInterval)
                guard !Task.isCancelled else { return }
                now = Date()
            }
        }
    }

    /// A small "N new" capsule that calls out conflicts a rescan just turned up, so
    /// the change registers without the user having to diff the list by eye. Only
    /// shown when there's something new; it isn't a permanent fixture of the header.
    private var newBadge: some View {
        Text(newConflictCount == 1 ? "1 new" : "\(newConflictCount) new")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.orange.opacity(0.15), in: Capsule())
            .help("Conflicts that appeared since the previous scan")
    }

    private var headline: String {
        guard realConflictCount > 0 else { return "No always-on conflicts" }
        let noun = realConflictCount == 1 ? "real conflict" : "real conflicts"
        return "\(realConflictCount) \(noun)"
    }

    private var subhead: String {
        let overlaps = appOverlapCount == 1 ? "1 menu overlap" : "\(appOverlapCount) menu overlaps"
        var text = "\(overlaps), only clash when an app is focused \u{00B7} scanned \(bindingCount) shortcuts in \(String(format: "%.1f", scanDuration))s"
        // Only ever absent on results that predate a completed scan, which the
        // header does not show anyway, but the type is honest about it.
        if let lastScanDate {
            text += " \u{00B7} \(ScanTimeFormatter.relativeDescription(since: lastScanDate, now: now))"
        }
        return text
    }
}
