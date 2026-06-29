import Foundation

/// Builds a shareable Markdown report of detected shortcut conflicts.
///
/// Pure value-in, string-out so it stays testable and free of UI concerns.
/// The view layer only handles the save panel and writing the result to disk.
enum ConflictReport {

    /// Renders the full conflict list as Markdown, grouped into real conflicts
    /// (always-on) and menu overlaps (focus-dependent), mirroring the on-screen
    /// ranking. Pass `rankedConflicts` so the report order matches the sidebar.
    static func markdown(
        conflicts: [Conflict],
        bindingCount: Int,
        scanDuration: TimeInterval,
        generatedAt: Date = .now
    ) -> String {
        let real = conflicts.filter { $0.category == .realConflict }
        let overlaps = conflicts.filter { $0.category == .appOverlap }

        var lines: [String] = []
        lines.append("# HotkeyClash Conflict Report")
        lines.append("")
        lines.append("Generated \(dateFormatter.string(from: generatedAt))")
        lines.append("")
        lines.append(summaryLine(real: real.count, overlaps: overlaps.count, bindingCount: bindingCount, scanDuration: scanDuration))
        lines.append("")

        if real.isEmpty && overlaps.isEmpty {
            lines.append("No conflicts found.")
            lines.append("")
            return lines.joined(separator: "\n")
        }

        if !real.isEmpty {
            lines.append("## Real conflicts")
            lines.append("")
            lines.append("These involve an always-on global or system shortcut, so they clash no matter which app is focused.")
            lines.append("")
            for conflict in real { lines += section(for: conflict) }
        }

        if !overlaps.isEmpty {
            lines.append("## Menu overlaps")
            lines.append("")
            lines.append("These are app menu shortcuts that share a combo. Each fires only when its own app is focused, so they rarely clash in practice.")
            lines.append("")
            for conflict in overlaps { lines += section(for: conflict) }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Sections

    private static func section(for conflict: Conflict) -> [String] {
        var lines: [String] = []
        let count = conflict.bindings.count
        lines.append("### \(conflict.displayString)  (\(count) \(count == 1 ? "app" : "apps"))")
        lines.append("")
        lines.append("Severity: \(severityText(conflict.severity))")
        lines.append("")
        for binding in sortedBindings(conflict.bindings) {
            lines.append("- **\(binding.ownerName)** (\(sourceLabel(binding.source))): \(binding.action)")
        }
        lines.append("")
        return lines
    }

    private static func summaryLine(real: Int, overlaps: Int, bindingCount: Int, scanDuration: TimeInterval) -> String {
        let realText = "\(real) real \(real == 1 ? "conflict" : "conflicts")"
        let overlapText = "\(overlaps) menu \(overlaps == 1 ? "overlap" : "overlaps")"
        let duration = String(format: "%.1f", scanDuration)
        return "Scanned \(bindingCount) shortcuts in \(duration)s. Found \(realText) and \(overlapText)."
    }

    // MARK: - Labels

    /// Mirrors `ConflictDetailView`'s source ordering: system first, then config,
    /// then menu bar, with apps alphabetical within a source.
    private static func sortedBindings(_ bindings: [HotkeyBinding]) -> [HotkeyBinding] {
        let order: [HotkeyBinding.BindingSource] = [.systemShortcut, .configFile, .menuBar]
        return bindings.sorted { lhs, rhs in
            let lhsIndex = order.firstIndex(of: lhs.source) ?? order.count
            let rhsIndex = order.firstIndex(of: rhs.source) ?? order.count
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
            return lhs.ownerName < rhs.ownerName
        }
    }

    private static func severityText(_ severity: Conflict.Severity) -> String {
        switch severity {
        case .definite: "Definite conflict (multiple global shortcuts on the same key)"
        case .potential: "Potential conflict (overlapping menu shortcuts across apps)"
        }
    }

    private static func sourceLabel(_ source: HotkeyBinding.BindingSource) -> String {
        switch source {
        case .menuBar: "Menu Bar"
        case .configFile: "Config"
        case .systemShortcut: "System"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
