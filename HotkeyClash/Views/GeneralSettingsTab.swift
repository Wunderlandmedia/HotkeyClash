import SwiftUI

struct GeneralSettingsTab: View {
    @State private var hasAccessibility = false
    private var settings: SettingsManager { .shared }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SettingsCard(title: "General") {
                    SettingsRow {
                        Text("Launch at login")
                        Spacer()
                        Toggle("Launch at login", isOn: Bindable(settings).launchAtLogin)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    SettingsRow(showDivider: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scan on launch")
                            Text("Automatically scan for shortcut conflicts when HotkeyClash starts")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("Scan on launch", isOn: Bindable(settings).scanOnLaunch)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }

                SettingsCard(title: "Accessibility") {
                    if hasAccessibility {
                        SettingsRow(showDivider: false) {
                            Label("Accessibility granted", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Spacer()
                        }
                    } else {
                        SettingsRow(showDivider: false) {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Accessibility permission required", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Text("HotkeyClash needs Accessibility access to read menu bar shortcuts from running apps.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("System Settings > Privacy & Security > Accessibility > enable HotkeyClash")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Button("Open System Settings") {
                                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                }

                SettingsCard(title: "Shortcut") {
                    SettingsRow(showDivider: false) {
                        Text("Global hotkey")
                        Spacer()
                        HotkeyRecorderView()
                    }
                }
            }
            .padding(20)
        }
        .background(Color("BrandBackground"))
        .onAppear {
            hasAccessibility = AccessibilityService.checkPermission()
        }
        .task {
            guard !hasAccessibility else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let granted = AccessibilityService.checkPermission()
                if granted != hasAccessibility {
                    hasAccessibility = granted
                }
                if granted { break }
            }
        }
    }
}
