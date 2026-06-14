import SwiftUI
import os

struct AboutSettingsTab: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)

                    Text("HotkeyClash")
                        .font(.title2.bold())

                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Find where your keyboard shortcuts clash.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                SettingsCard(title: "License") {
                    SettingsRow(showDivider: false) {
                        Text("GPL-2.0")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let url = URL(string: "https://www.gnu.org/licenses/old-licenses/gpl-2.0.html") {
                            Link("View License", destination: url)
                                .font(.caption)
                        }
                    }
                }

                SettingsCard(title: "Also by Wunderlandmedia") {
                    SettingsRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("QuietClip")
                                .fontWeight(.medium)
                            Text("Privacy-first clipboard manager")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let url = URL(string: "https://quietclip.app") {
                            Link("Website", destination: url)
                                .font(.caption)
                        }
                    }
                    SettingsRow(showDivider: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("WunderType")
                                .fontWeight(.medium)
                            Text("AI text correction for macOS")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let url = URL(string: "https://wundertype.com") {
                            Link("Website", destination: url)
                                .font(.caption)
                        }
                    }
                }

                SettingsCard(title: "Support Development") {
                    SettingsRow(showDivider: false) {
                        Text("HotkeyClash is free and open source.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let url = URL(string: "https://github.com/sponsors/wunderlandmedia") {
                            Link("GitHub Sponsors", destination: url)
                                .font(.caption)
                        }
                    }
                }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 4) {
                Text("Made by")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let url = URL(string: "https://wunderlandmedia.com") {
                    Link("Wunderlandmedia", destination: url)
                        .font(.caption)
                }
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let url = URL(string: "https://hotkeyclash.com") {
                    Link("Website", destination: url)
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color("BrandBackground"))
        }
        .background(Color("BrandBackground"))
    }
}
