import SwiftUI

/// The failed-search state when the query spells out a key combo: rather than
/// "no conflicts match", it says what owns that combo, or that nothing does.
///
/// Lives in the narrow sidebar, so each owner gets a compact two-line entry
/// instead of the full `BindingRow` with its icon and badges.
struct ComboLookupView: View {
    let displayString: String
    let owners: [HotkeyBinding]

    var body: some View {
        if owners.isEmpty {
            ContentUnavailableView {
                Label("\(displayString) is free", systemImage: "checkmark.circle")
            } description: {
                // Honest about the limit: menu shortcuts come from running apps,
                // so a closed app can still own this combo.
                Text("Nothing HotkeyClash scanned uses this shortcut. Apps that were not running during the scan are not covered.")
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(displayString) is used by")
                        .scaledFont(.headline)

                    ForEach(owners) { binding in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(binding.ownerName)
                                .scaledFont(.body, weight: .semibold)
                            Text(binding.action)
                                .scaledFont(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Text(footnote)
                        .scaledFont(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
    }

    /// One owner is the usual case: taken, but not a clash. Two or more only
    /// reach this screen when the severity filter hid the conflict.
    private var footnote: String {
        owners.count == 1
            ? "Not a conflict: nothing else claims this shortcut."
            : "This is a conflict, hidden by the current filter."
    }
}
