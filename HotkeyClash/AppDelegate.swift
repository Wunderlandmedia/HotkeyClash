import AppKit
import SwiftUI
import os

private let logger = Logger(subsystem: "com.hotkeyclash.app", category: "AppDelegate")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusBar: StatusBarController!
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private let scanner = ShortcutScanner()
    private var scanTask: Task<Void, Never>?
    private var didCompleteSetup = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !SettingsManager.shared.hasCompletedOnboarding {
            showOnboarding()
            return
        }

        completeAppSetup()
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        NSApp.activate()

        let onboardingView = OnboardingView { [weak self] in
            SettingsManager.shared.hasCompletedOnboarding = true
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            self?.completeAppSetup()
        }

        let controller = NSHostingController(rootView: onboardingView)
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable]
        window.title = "Welcome to HotkeyClash"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        onboardingWindow = window
    }

    // Closing the onboarding window early (red button) is treated as finishing it,
    // so the app still installs its menu bar item instead of running headless.
    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow == onboardingWindow else { return }
        guard !SettingsManager.shared.hasCompletedOnboarding else { return }
        SettingsManager.shared.hasCompletedOnboarding = true
        onboardingWindow = nil
        completeAppSetup()
    }

    // MARK: - App Setup

    private func completeAppSetup() {
        guard !didCompleteSetup else { return }
        didCompleteSetup = true

        statusBar = StatusBarController()

        let contentView = ConflictListView(scanner: scanner)
        statusBar.setup(with: contentView)

        let settings = SettingsManager.shared
        HotKeyManager.shared.register(
            keyCode: settings.globalShortcutKeyCode,
            modifiers: settings.globalShortcutModifiers
        ) { [weak self] in
            self?.statusBar.showPopover()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettings),
            name: .openSettings,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRescan),
            name: .triggerRescan,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDismissPanel),
            name: .dismissPanel,
            object: nil
        )

        // Scan on launch if enabled and AX permission is granted
        if settings.scanOnLaunch && AccessibilityService.checkPermission() {
            startScan(rescan: false)
        }

        logger.info("HotkeyClash launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregister()
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        // Size the window to SettingsView's fixed content via the hosting
        // controller so the window frame matches the SwiftUI content exactly.
        let controller = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable]
        window.title = "HotkeyClash Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        settingsWindow = window
    }

    @objc private func handleRescan() {
        startScan(rescan: true)
    }

    @objc private func handleDismissPanel() {
        statusBar.hidePopover()
    }

    /// Runs a scan, superseding any in-flight one, then refreshes the menu bar badge.
    private func startScan(rescan: Bool) {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            guard let self else { return }
            if rescan {
                await scanner.rescan()
            } else {
                await scanner.scan()
            }
            guard !Task.isCancelled else { return }
            // The badge counts always-on clashes; focus-dependent menu overlaps are
            // not real conflicts and would only inflate the number with noise.
            statusBar.updateBadge(count: scanner.realConflictCount)
        }
    }
}
