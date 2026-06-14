import Carbon
import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class SettingsManager {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let launchAtLogin = "launchAtLogin"
        static let scanOnLaunch = "scanOnLaunch"
        static let globalShortcutKeyCode = "globalShortcutKeyCode"
        static let globalShortcutModifiers = "globalShortcutModifiers"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    static let defaultShortcutKeyCode: UInt32 = 0x04 // H
    static let defaultShortcutModifiers: UInt32 = UInt32(cmdKey | shiftKey)

    private init() {
        defaults.register(defaults: [
            Keys.launchAtLogin: false,
            Keys.scanOnLaunch: true,
            Keys.globalShortcutKeyCode: Self.defaultShortcutKeyCode,
            Keys.globalShortcutModifiers: Self.defaultShortcutModifiers
        ])

        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        scanOnLaunch = defaults.bool(forKey: Keys.scanOnLaunch)
        globalShortcutKeyCode = UInt32(defaults.integer(forKey: Keys.globalShortcutKeyCode))
        globalShortcutModifiers = UInt32(defaults.integer(forKey: Keys.globalShortcutModifiers))
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }

    var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            if launchAtLogin {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        }
    }

    var scanOnLaunch: Bool {
        didSet { defaults.set(scanOnLaunch, forKey: Keys.scanOnLaunch) }
    }

    var globalShortcutKeyCode: UInt32 {
        didSet { defaults.set(globalShortcutKeyCode, forKey: Keys.globalShortcutKeyCode) }
    }

    var globalShortcutModifiers: UInt32 {
        didSet { defaults.set(globalShortcutModifiers, forKey: Keys.globalShortcutModifiers) }
    }
}
