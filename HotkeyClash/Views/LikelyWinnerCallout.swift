import SwiftUI

/// The "who actually wins?" callout at the top of a conflict's detail pane.
///
/// It leads with the verdict and follows with the reasoning, because the
/// reasoning is what makes the guess trustworthy. When the layers tie we say
/// that plainly instead of inventing a winner.
struct LikelyWinnerCallout: View {
    let verdict: LikelyWinner

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: iconName)
                .font(.caption)
                .foregroundStyle(tint)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)

                Text(verdict.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var headline: String {
        switch verdict {
        case .likely: "Likely winner"
        case .tied: "Too close to call"
        case .focusDependent: "No contest"
        }
    }

    private var iconName: String {
        switch verdict {
        case .likely: "checkmark.seal"
        case .tied: "questionmark.circle"
        case .focusDependent: "hand.raised"
        }
    }

    private var tint: Color {
        switch verdict {
        case .likely: .green
        case .tied: .orange
        case .focusDependent: .secondary
        }
    }
}
