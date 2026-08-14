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
        static let scanRunningApps = "scanRunningApps"
        static let scanConfigFiles = "scanConfigFiles"
        static let scanSystemShortcuts = "scanSystemShortcuts"
        static let includeBackgroundApps = "includeBackgroundApps"
        static let autoRescanOnAppChange = "autoRescanOnAppChange"
        static let notifyOnNewConflicts = "notifyOnNewConflicts"
        static let panelOriginX = "panelOriginX"
        static let panelOriginY = "panelOriginY"
        static let hasSavedPanelOrigin = "hasSavedPanelOrigin"
    }

    static let defaultShortcutKeyCode: UInt32 = 0x04 // H
    static let defaultShortcutModifiers: UInt32 = UInt32(cmdKey | shiftKey)

    private init() {
        defaults.register(defaults: [
            Keys.launchAtLogin: false,
            Keys.scanOnLaunch: true,
            Keys.globalShortcutKeyCode: Self.defaultShortcutKeyCode,
            Keys.globalShortcutModifiers: Self.defaultShortcutModifiers,
            Keys.scanRunningApps: true,
            Keys.scanConfigFiles: true,
            Keys.scanSystemShortcuts: true,
            Keys.includeBackgroundApps: true,
            Keys.autoRescanOnAppChange: true
        ])

        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        scanOnLaunch = defaults.bool(forKey: Keys.scanOnLaunch)
        globalShortcutKeyCode = UInt32(defaults.integer(forKey: Keys.globalShortcutKeyCode))
        globalShortcutModifiers = UInt32(defaults.integer(forKey: Keys.globalShortcutModifiers))
        scanRunningApps = defaults.bool(forKey: Keys.scanRunningApps)
        scanConfigFiles = defaults.bool(forKey: Keys.scanConfigFiles)
        scanSystemShortcuts = defaults.bool(forKey: Keys.scanSystemShortcuts)
        includeBackgroundApps = defaults.bool(forKey: Keys.includeBackgroundApps)
        autoRescanOnAppChange = defaults.bool(forKey: Keys.autoRescanOnAppChange)
        notifyOnNewConflicts = defaults.bool(forKey: Keys.notifyOnNewConflicts)
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

    // MARK: - Scan sources

    /// Scan menu bar shortcuts of running apps (needs Accessibility permission).
    var scanRunningApps: Bool {
        didSet { defaults.set(scanRunningApps, forKey: Keys.scanRunningApps) }
    }

    /// Scan automation tool config files (Karabiner-Elements, skhd, Keyboard Maestro, BetterTouchTool).
    var scanConfigFiles: Bool {
        didSet { defaults.set(scanConfigFiles, forKey: Keys.scanConfigFiles) }
    }

    /// Scan macOS system (symbolic) hotkeys.
    var scanSystemShortcuts: Bool {
        didSet { defaults.set(scanSystemShortcuts, forKey: Keys.scanSystemShortcuts) }
    }

    /// Include menu-bar-only / agent apps (LSUIElement, no Dock icon) when scanning
    /// running apps. Their status-item menus are scanned; their inherited main menu
    /// is skipped to avoid sweeping in invisible system agents.
    var includeBackgroundApps: Bool {
        didSet { defaults.set(includeBackgroundApps, forKey: Keys.includeBackgroundApps) }
    }

    /// Rescan by itself when apps launch or quit, so the results and the badge do
    /// not quietly go stale. On by default: a wrong count is worse than a scan.
    var autoRescanOnAppChange: Bool {
        didSet { defaults.set(autoRescanOnAppChange, forKey: Keys.autoRescanOnAppChange) }
    }

    /// Post a notification when a background rescan turns up conflicts that weren't
    /// there before. Off by default and needs the OS notification permission, so it
    /// stays silent until the user asks for it (unlike the always-useful auto rescan
    /// above, which only reads what is already on screen).
    var notifyOnNewConflicts: Bool {
        didSet { defaults.set(notifyOnNewConflicts, forKey: Keys.notifyOnNewConflicts) }
    }

    // MARK: - Panel position

    /// Where the user last left the panel, in screen coordinates.
    ///
    /// Stored as two doubles rather than an archived point because that survives
    /// every plist round trip without a coder. Reading back nil means "never
    /// moved", which the panel treats as "centre me", and so does a saved spot
    /// that no longer lands on a connected display.
    var panelOrigin: CGPoint? {
        get {
            guard defaults.bool(forKey: Keys.hasSavedPanelOrigin) else { return nil }
            return CGPoint(
                x: defaults.double(forKey: Keys.panelOriginX),
                y: defaults.double(forKey: Keys.panelOriginY)
            )
        }
        set {
            guard let newValue else {
                defaults.set(false, forKey: Keys.hasSavedPanelOrigin)
                return
            }
            defaults.set(newValue.x, forKey: Keys.panelOriginX)
            defaults.set(newValue.y, forKey: Keys.panelOriginY)
            defaults.set(true, forKey: Keys.hasSavedPanelOrigin)
        }
    }
}
