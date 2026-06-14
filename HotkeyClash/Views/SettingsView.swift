import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                GeneralSettingsTab()
            }
            Tab("About", systemImage: "info.circle") {
                AboutSettingsTab()
            }
        }
        .frame(width: 460, height: 420)
        .fixedSize()
    }
}
