import SwiftUI

/// The right-hand side of the split: either the full detail for the selected
/// conflict, or a gentle "nothing picked yet" placeholder.
///
/// Thin wrapper on purpose. It keeps the empty-state and the scrolling/`.id`
/// plumbing out of `ConflictDetailView`, so that view can stay purely about
/// rendering one conflict.
struct ConflictDetailPane: View {
    let conflict: Conflict?

    var body: some View {
        Group {
            if let conflict {
                ScrollView {
                    ConflictDetailView(conflict: conflict)
                        .padding(20)
                        // Tie the identity to the conflict so switching selection
                        // resets scroll position instead of animating between them.
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
