import SwiftUI

struct ConflictListView: View {
    var scanner: ShortcutScanner

    @State private var selectedID: Conflict.ID?

    private var selectedConflict: Conflict? {
        scanner.conflicts.first { $0.id == selectedID }
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
        .onChange(of: scanner.conflicts) {
            // Conflicts arrive pre-sorted from the detector (definite first, then
            // most clashes first). Keep the selection valid as results change.
            if selectedID == nil || !scanner.conflicts.contains(where: { $0.id == selectedID }) {
                selectedID = scanner.conflicts.first?.id
            }
        }
    }

    private var splitResultsView: some View {
        VStack(spacing: 0) {
            ResultsHeader(
                conflictCount: scanner.conflictCount,
                definiteCount: scanner.definiteConflictCount,
                bindingCount: scanner.allBindings.count,
                scanDuration: scanner.scanDuration,
                onRescan: {
                    selectedID = nil
                    Task { await scanner.rescan() }
                }
            )
            Divider()
            HStack(spacing: 0) {
                // A List with a selection binding gives keyboard navigation, type
                // select, and VoiceOver list semantics for free.
                List(scanner.conflicts, selection: $selectedID) { conflict in
                    ConflictRow(conflict: conflict)
                        .tag(conflict.id)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(width: 260)
                Divider()
                ConflictDetailPane(conflict: selectedConflict)
            }
        }
    }
}

// MARK: - Detail pane (dedicated view struct)

private struct ConflictDetailPane: View {
    let conflict: Conflict?

    var body: some View {
        Group {
            if let conflict {
                ScrollView {
                    ConflictDetailView(conflict: conflict)
                        .padding(20)
                        .id(conflict.id)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 32))
                        .foregroundStyle(.quaternary)
                    Text("Select a conflict")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("BrandBackground").opacity(0.5))
    }
}

// MARK: - Header

private struct ResultsHeader: View {
    let conflictCount: Int
    let definiteCount: Int
    let bindingCount: Int
    let scanDuration: TimeInterval
    let onRescan: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if definiteCount > 0 {
                    Text("\(conflictCount) conflicts (\(definiteCount) definite)")
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text("\(conflictCount) potential conflicts")
                        .font(.subheadline.weight(.semibold))
                }
                Text("Scanned \(bindingCount) shortcuts in \(String(format: "%.1f", scanDuration))s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Rescan", action: onRescan)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Idle

private struct IdleView: View {
    let onScan: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "keyboard")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Find shortcut conflicts")
                .font(.headline)
            Text("Scans running apps, config files, and system shortcuts for overlapping key combos.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                onScan()
            } label: {
                Text("Scan")
                    .font(.headline)
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text("Accessibility permission is needed to read app menu shortcuts.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .padding()
    }
}

// MARK: - Scanning

private struct ScanningView: View {
    let progress: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(progress)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }
}

// MARK: - Empty Results

private struct EmptyResultsView: View {
    let bindingCount: Int
    let scanDuration: TimeInterval
    let onRescan: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ContentUnavailableView(
                "No Conflicts Found",
                systemImage: "checkmark.circle",
                description: Text("All \(bindingCount) shortcuts are unique. Scanned in \(String(format: "%.1f", scanDuration))s.")
            )
            Button("Rescan", action: onRescan)
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding()
    }
}

// MARK: - Error

private struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("Scan Failed")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if message.lowercased().contains("accessibility") {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                    // Dismiss the panel as System Settings opens, so the user isn't
                    // left looking at the permission screen behind it. They reopen
                    // from the menu bar and scan once access is granted.
                    NotificationCenter.default.post(name: .dismissPanel, object: nil)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding()
    }
}
