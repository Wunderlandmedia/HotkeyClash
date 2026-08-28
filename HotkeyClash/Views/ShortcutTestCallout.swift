import SwiftUI

/// The live test, sitting directly under the static guess it exists to check.
///
/// Placement is the argument: the guess says who it thinks wins, and immediately
/// below it is the button that finds out for real. When the two disagree, the
/// disagreement is said out loud rather than left for the user to spot.
struct ShortcutTestCallout: View {
    let conflict: Conflict
    var tester: ShortcutTester

    /// The tester is shared across the whole panel, so anything it is holding
    /// belongs to whichever conflict started it, not necessarily this one.
    private var state: ShortcutTester.State {
        tester.conflictID == conflict.id ? tester.state : .idle
    }

    var body: some View {
        Group {
            switch state {
            case .idle:
                prompt
            case .unavailable(let reason):
                unavailable(reason)
            case .listening(let secondsRemaining):
                listening(secondsRemaining: secondsRemaining)
            case .finished:
                // Always present for a finished test of this conflict; the tester
                // builds it so the binding list below can mark the same winner.
                if let verdict = tester.verdict(for: conflict) {
                    finished(verdict: verdict)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - States

    private var prompt: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "wave.3.right")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Not sure? Watch a real keypress")
                    .font(.caption.weight(.semibold))
                Text("HotkeyClash steps out of the way, you press \(conflict.displayString), and it reports what happened to the key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("Test") { tester.start(for: conflict) }
                .controlSize(.small)
        }
    }

    private func unavailable(_ reason: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.top, 1)

            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button("Try Again") { tester.start(for: conflict) }
                .controlSize(.small)
        }
    }

    private func listening(secondsRemaining: Int) -> some View {
        HStack(alignment: .center, spacing: 8) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text("Listening. Press \(conflict.displayString) now.")
                    .font(.caption.weight(.semibold))
                Text("Focus went back to the app you were in. Click into a different one first if you want to test it there. \(secondsRemaining)s left.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("Cancel") { tester.cancel() }
                .controlSize(.small)
        }
    }

    private func finished(verdict: ShortcutTestVerdict) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: verdict.iconName)
                .font(.caption)
                .foregroundStyle(tint(for: verdict.tone))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(verdict.headline)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint(for: verdict.tone))

                Text(verdict.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let note = disagreementNote(for: verdict) {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Button("Test Again") { tester.start(for: conflict) }
                .controlSize(.small)
        }
    }

    // MARK: - Verdict

    /// Calls out the case worth knowing about: the live test found a different
    /// winner than the layer heuristic predicted. That is the heuristic being
    /// wrong, and burying it would defeat the point of testing at all.
    private func disagreementNote(for verdict: ShortcutTestVerdict) -> String? {
        guard case .likely(let predicted, _) = conflict.likelyWinner else { return nil }
        switch verdict {
        case .reachedApp(let binding, _) where binding.id != predicted.id:
            return "The guess above named \(predicted.ownerName). This is what actually happened."
        case .swallowedByTap(let candidates) where candidates.count == 1 && candidates[0] != predicted.ownerName:
            return "The guess above named \(predicted.ownerName). This is what actually happened."
        case .unregisteredApp:
            return "The guess above named \(predicted.ownerName), which the scan knows about. This one it does not."
        default:
            return nil
        }
    }

    private func tint(for tone: ShortcutTestVerdict.Tone) -> Color {
        switch tone {
        case .confirmed: .green
        case .informative: .blue
        case .inconclusive: .secondary
        }
    }
}
