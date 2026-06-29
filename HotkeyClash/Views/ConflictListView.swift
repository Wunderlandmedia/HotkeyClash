import SwiftUI
import UniformTypeIdentifiers

/// The heart of the panel: a master-detail view over the scan results.
///
/// This view is really the conductor. The actual pieces it arranges, the search
/// field, the summary header, the detail pane, and the various scan-state
/// placeholders, each live in their own file so this one can stay about wiring
/// them together: filtering the list, keeping a sane selection, and exporting.
struct ConflictListView: View {
    var scanner: ShortcutScanner

    @State private var selectedID: Conflict.ID?

    /// The query the list filters on. The search field owns its own live text and
    /// only writes here after a debounce, so typing never invalidates this view's
    /// body (the 125-row List, header, and detail pane). The heavy work runs once
    /// typing settles, not on every keystroke.
    @State private var debouncedQuery = ""

    /// How long typing must pause before filtering runs. ~250ms is the sweet spot:
    /// short enough to feel responsive, long enough to skip intermediate keystrokes. At least that's what I think lol.
    private static let searchDebounce = Duration.milliseconds(250)

    /// Per-conflict word list for searching, built once per scan rather than on
    /// every keystroke. Keyed by conflict id. Words come from the spelled-out combo
    /// (so "shift"/"cmd" match glyph combos), app names, and actions.
    @State private var searchIndex: [Conflict.ID: [String]] = [:]

    private var rankedConflicts: [Conflict] {
        scanner.rankedConflicts
    }

    /// The sidebar list after applying the search filter. Each whitespace-separated
    /// token must prefix-match some word in the precomputed index, with AND semantics
    /// across tokens, so "cmd shift c" narrows in any order. Prefix (not substring)
    /// matching keeps "p" from matching the middle of "WhatsApp". Empty query shows
    /// everything. Driven by `debouncedQuery`, not `searchText`.
    private var filteredConflicts: [Conflict] {
        let tokens = debouncedQuery.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return rankedConflicts }
        return rankedConflicts.filter { conflict in
            guard let words = searchIndex[conflict.id] else { return false }
            return tokens.allSatisfy { token in words.contains { $0.hasPrefix(token) } }
        }
    }

    /// Rebuilds the word index from the current scan results. Called when the
    /// conflict set changes, not per keystroke.
    private func rebuildSearchIndex() {
        var index: [Conflict.ID: [String]] = [:]
        for conflict in scanner.conflicts {
            var words = conflict.searchableText.split(separator: " ").map(String.init)
            for binding in conflict.bindings {
                words += tokenize(binding.ownerName)
                words += tokenize(binding.action)
            }
            index[conflict.id] = words
        }
        searchIndex = index
    }

    /// Splits free text into lowercased alphanumeric word tokens for the index.
    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private var selectedConflict: Conflict? {
        rankedConflicts.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(spacing: 0) {
            switch scanner.state {
            case .idle:
                IdleView(onScan: { Task { await scanner.scan() } })
            case .scanning(let progress):
                ScanningView(progress: progress)
            case .completed:
                if scanner.conflicts.isEmpty {
                    EmptyResultsView(
                        bindingCount: scanner.allBindings.count,
                        scanDuration: scanner.scanDuration,
                        onRescan: { Task { await scanner.rescan() } }
                    )
                } else {
                    splitResultsView
                }
            case .error(let message):
                ErrorView(message: message, onRetry: { Task { await scanner.scan() } })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("BrandBackground"))
        .onChange(of: scanner.conflicts, initial: true) {
            // Rebuild the search index once when a scan produces new results,
            // not on every keystroke.
            rebuildSearchIndex()
        }
        .onChange(of: filteredConflicts) {
            // Real conflicts pin to the top, app overlaps follow, and the search
            // filter narrows the list. Keep the selection on a visible row as
            // results or the query change.
            if selectedID == nil || !filteredConflicts.contains(where: { $0.id == selectedID }) {
                selectedID = filteredConflicts.first?.id
            }
        }
    }

    private var splitResultsView: some View {
        VStack(spacing: 0) {
            // Search is pinned at the very top so it is always reachable, then the
            // summary toolbar, then the master-detail split.
            ConflictSearchField(query: $debouncedQuery, debounce: Self.searchDebounce)
            Divider()
            ResultsHeader(
                realConflictCount: scanner.realConflictCount,
                appOverlapCount: scanner.appOverlapCount,
                bindingCount: scanner.allBindings.count,
                scanDuration: scanner.scanDuration,
                onRescan: {
                    selectedID = nil
                    debouncedQuery = ""
                    Task { await scanner.rescan() }
                },
                onExport: exportReport
            )
            Divider()
            HStack(spacing: 0) {
                sidebarList
                Divider()
                ConflictDetailPane(conflict: selectedConflict)
            }
        }
    }

    private var sidebarList: some View {
        Group {
            if filteredConflicts.isEmpty {
                ContentUnavailableView.search(text: debouncedQuery)
            } else {
                // A List with a selection binding gives keyboard navigation, type
                // select, and VoiceOver list semantics for free.
                List(filteredConflicts, selection: $selectedID) { conflict in
                    ConflictRow(conflict: conflict)
                        .tag(conflict.id)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(width: 260)
    }

    /// Renders the current conflicts to Markdown and writes them to a user-chosen
    /// file. Uses the ranked (not filtered) list so the export is always complete,
    /// independent of any active search.
    private func exportReport() {
        let markdown = ConflictReport.markdown(
            conflicts: rankedConflicts,
            bindingCount: scanner.allBindings.count,
            scanDuration: scanner.scanDuration
        )
        let panel = NSSavePanel()
        panel.title = "Export Conflict Report"
        panel.nameFieldStringValue = "HotkeyClash-Conflicts.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
