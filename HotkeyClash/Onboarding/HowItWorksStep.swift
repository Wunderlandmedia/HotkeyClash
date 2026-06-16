import SwiftUI

struct HowItWorksStep: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "keyboard")
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text("How HotkeyClash Works")
                .font(.largeTitle)
                .bold()

            Text("HotkeyClash gathers every keyboard shortcut on your Mac and shows you where they collide.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 14) {
                HowItWorksFeature(icon: "macwindow", text: "Reads menu bar shortcuts from your running apps")
                Divider()
                HowItWorksFeature(icon: "doc.text", text: "Parses Karabiner-Elements and skhd config files")
                Divider()
                HowItWorksFeature(icon: "gearshape", text: "Checks built-in macOS system shortcuts")
                Divider()
                HowItWorksFeature(icon: "exclamationmark.triangle", text: "Flags every key combo claimed more than once")
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color("BrandBackground"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color("BrandBorder"), lineWidth: 1)
            )
            .padding(.horizontal, 40)

            Spacer()

            Button(action: onContinue) {
                Text("Continue")
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
                .frame(height: 30)
        }
        .padding(.horizontal, 40)
    }
}

struct HowItWorksFeature: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)

            Text(text)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()
        }
    }
}
