import AppKit
import SwiftUI

struct AccessibilityStep: View {
    var onContinue: () -> Void

    @State private var granted = AccessibilityService.checkPermission()

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: granted ? "checkmark.shield.fill" : "lock.shield")
                .font(.system(size: 52))
                .foregroundStyle(granted ? .green : Color.accentColor)
                .accessibilityHidden(true)

            Text("Enable Accessibility")
                .font(.largeTitle)
                .bold()

            Text("To read the menu shortcuts of your running apps, macOS needs you to grant HotkeyClash Accessibility access. Config files and system shortcuts are scanned without it.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 12) {
                AccessibilityStepRow(number: 1, text: "Click Grant Access below")
                AccessibilityStepRow(number: 2, text: "Turn on HotkeyClash in the list that opens")
                AccessibilityStepRow(number: 3, text: "Come back here to continue")
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

            if granted {
                Label("Accessibility granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                Button(action: onContinue) {
                    Text("Continue")
                        .frame(maxWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button(action: requestAccess) {
                    Text("Grant Access")
                        .frame(maxWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Skip for now", action: onContinue)
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
                .frame(height: 30)
        }
        .padding(.horizontal, 40)
        .task {
            // Poll until granted so the step flips itself once the user toggles it
            // on in System Settings, without needing to return and click anything.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let current = AccessibilityService.checkPermission()
                if current != granted { granted = current }
                if current { break }
            }
        }
    }

    private func requestAccess() {
        AccessibilityService.requestPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct AccessibilityStepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))

            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)

            Spacer()
        }
    }
}
