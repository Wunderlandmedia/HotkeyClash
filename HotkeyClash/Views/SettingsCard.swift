import SwiftUI

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                content
            }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color("BrandBorder"), lineWidth: 1)
            )
        }
    }
}

struct SettingsRow<Content: View>: View {
    let showDivider: Bool
    @ViewBuilder let content: Content

    init(showDivider: Bool = true, @ViewBuilder content: () -> Content) {
        self.showDivider = showDivider
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if showDivider {
                Divider()
                    .padding(.leading, 16)
            }
        }
    }
}
