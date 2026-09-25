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
    private var workspaceWatcher: WorkspaceWatcher?
    private let conflictNotifier = ConflictNotifier()
    private var shortcutTester: ShortcutTester!

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

        // The tester has two dependencies that only live out here: which app the
        // panel opened over (it hands focus back so the test happens somewhere
        // realistic), and the panel's click-outside dismissal, which has to stand
        // down while the user clicks into another app to press the key.
        shortcutTester = ShortcutTester(
            appToRestore: { [weak self] in self?.statusBar.previousApp },
            onListeningChanged: { [weak self] isListening in
                self?.statusBar.setDismissSuspended(isListening)
            }
        )

        let contentView = ConflictListView(scanner: scanner, tester: shortcutTester)
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePanelPinChanged),
            name: .panelPinChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePanelTextSizeChanged),
            name: .panelTextSizeChanged,
            object: nil
        )

        startWorkspaceWatcher()

        // Scan on launch if enabled and AX permission is granted
        if settings.scanOnLaunch && AccessibilityService.checkPermission() {
            startScan(rescan: false)
        }

        logger.info("HotkeyClash launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        workspaceWatcher?.stop()
        shortcutTester?.cancel()
        HotKeyManager.shared.unregister()
    }

    // MARK: - Auto rescan

    /// Keeps the results honest as apps come and go. The watcher notices the churn;
    /// the conditions below decide whether acting on it is welcome.
    private func startWorkspaceWatcher() {
        let watcher = WorkspaceWatcher(
            shouldRescan: { [weak self] in
                guard let self else { return false }
                guard SettingsManager.shared.autoRescanOnAppChange else { return false }
                // A scan that cannot read app menus would come back with less than
                // the results already on screen, which is worse than being stale.
                guard AccessibilityService.checkPermission() else { return false }
                // Never rebuild the list out from under someone reading it. A
                // pinned panel is the exception: it can sit there for hours, so
                // refusing to scan would leave it permanently stale. Once the user
                // has switched to another app they are not reading it, and a fresh
                // list is worth more than a frozen one.
                guard statusBar.isPanelVisible else { return true }
                return SettingsManager.shared.keepPanelOpen && !NSApp.isActive
            },
            onRescan: { [weak self] in
                self?.startScan(rescan: true, notifyOnNewConflicts: true)
            }
        )
        watcher.start()
        workspaceWatcher = watcher
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

    @objc private func handlePanelPinChanged() {
        statusBar.refreshDismissBehavior()
    }

    @objc private func handlePanelTextSizeChanged() {
        statusBar.refreshTextSize()
    }

    /// Runs a scan and then refreshes the menu bar badge, queueing behind any scan
    /// already in flight.
    ///
    /// This used to cancel the previous task and start a fresh one, which quietly
    /// did the wrong thing. Cancellation is cooperative and the scan body never
    /// checks for it, so the old scan kept running regardless; the replacement then
    /// found the scanner busy, returned immediately without scanning, and updated
    /// the badge from the stale counts. Rare when the only trigger was an impatient
    /// double click, but the auto rescan makes app churn a trigger too. Waiting for
    /// the previous task means every request produces a real scan and a badge that
    /// matches it. Nothing can pile up here: the Rescan button is off screen while
    /// a scan runs, and the watcher debounces before it asks.
    private func startScan(rescan: Bool, notifyOnNewConflicts: Bool = false) {
        let previous = scanTask
        scanTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            if rescan {
                await scanner.rescan()
            } else {
                await scanner.scan()
            }
            // The badge counts always-on clashes; focus-dependent menu overlaps are
            // not real conflicts and would only inflate the number with noise.
            statusBar.updateBadge(count: scanner.realConflictCount)

            // Only the background auto rescan notifies, and only about conflicts that
            // are actually new. If the user opened the panel while the scan ran they
            // can see the change for themselves, so there is nothing to announce.
            if notifyOnNewConflicts,
               SettingsManager.shared.notifyOnNewConflicts,
               !statusBar.isPanelVisible,
               !scanner.newConflicts.isEmpty {
                conflictNotifier.notify(newConflicts: scanner.newConflicts)
            }
        }
    }
}
