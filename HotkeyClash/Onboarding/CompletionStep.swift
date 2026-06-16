import SwiftUI

struct CompletionStep: View {
    var onFinish: () -> Void

    private var settings: SettingsManager { .shared }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text("You're All Set")
                .font(.largeTitle)
                .bold()

            VStack(alignment: .leading, spacing: 12) {
                SummaryRow(
                    label: "Open shortcut",
                    value: ShortcutFormatter.displayString(
                        keyCode: settings.globalShortcutKeyCode,
                        carbonModifiers: settings.globalShortcutModifiers
                    )
                )
                SummaryRow(
                    label: "Accessibility",
                    value: AccessibilityService.checkPermission() ? "Granted" : "Not granted"
                )
            }
            .padding(20)
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 60)

            Divider()
                .padding(.horizontal, 80)

            VStack(spacing: 8) {
                Text("Quick Start")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Label("Click the menu bar icon to open HotkeyClash", systemImage: "1.circle")
                    Label("Press Scan to find shortcut conflicts", systemImage: "2.circle")
                    Label("Select a conflict to see which apps clash", systemImage: "3.circle")
                }
            }

            Spacer()

            Button(action: onFinish) {
                Text("Start Using HotkeyClash")
                    .frame(maxWidth: 240)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 30)
        }
    }
}
