import SwiftUI

/// The search box pinned at the top of the results panel.
///
/// The trick here: this view owns its own live `text`. We deliberately keep the
/// fast-changing string local so that hammering the keyboard only repaints this
/// little field and never the 125-row list behind it. The parent only hears about
/// a new query once the user pauses, via the debounce below. Learned that one the
/// hard way watching the whole panel stutter on every keystroke.
struct ConflictSearchField: View {
    /// The debounced query handed up to the parent to actually filter on.
    @Binding var query: String
    let debounce: Duration

    @State private var text = ""

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Filter by app, action, or key (e.g. shift, cmd c)", text: $text)
                .textFieldStyle(.plain)
                .font(.caption)
            // Only show the clear button once there's something to clear.
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .task(id: text) {
            // Each keystroke restarts this task and cancels the previous sleep, so
            // we only push a query up once typing settles. Clearing the field, on
            // the other hand, should feel instant, so skip the wait when it's empty.
            if text.isEmpty {
                query = ""
                return
            }
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            query = text
        }
        .onChange(of: query) {
            // If the parent wipes the query out from under us (e.g. on a rescan),
            // mirror that back into the field so they never drift apart.
            if query.isEmpty && !text.isEmpty {
                text = ""
            }
        }
    }
}
