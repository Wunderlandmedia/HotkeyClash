import AppKit
import SwiftUI

struct WelcomeStep: View {
    var onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 120)
                .accessibilityHidden(true)

            Text("Welcome to HotkeyClash")
                .font(.largeTitle)
                .bold()

            Text("Find where your keyboard shortcuts clash.\nHotkeyClash scans your apps, config files, and system shortcuts for conflicts.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()

            Button(action: onGetStarted) {
                Text("Get Started")
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
                .frame(height: 40)
        }
        .padding(.horizontal, 40)
    }
}
