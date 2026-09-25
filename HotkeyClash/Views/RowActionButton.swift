import SwiftUI

struct RowActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: icon, action: action)
            .labelStyle(.iconOnly)
            .scaledFont(.callout)
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
    }
}
