import SwiftUI

// The four "what should the panel show right now" states, grouped together since
// they're really one family: the placeholders the results view falls back to when
// there isn't a list of conflicts to show. Keeping them side by side makes the
// whole state machine easy to read in one place.

// MARK: - Idle

/// Before the first scan. A friendly nudge plus the big Scan button.
struct IdleView: View {
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
            // Set expectations up front so the permission prompt isn't a surprise.
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

/// While a scan is in flight. Just a spinner and the current step.
struct ScanningView: View {
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

/// The happy ending: scan finished and found nothing clashing. Rare, but nice
/// when it happens.
struct EmptyResultsView: View {
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

/// Something went wrong, usually a missing Accessibility grant. When that's the
/// case we send the user straight to the right System Settings pane rather than
/// making them hunt for it.
struct ErrorView: View {
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
                    // left staring at the permission screen behind it. They reopen
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
