import AppKit
import os

private let logger = Logger(subsystem: "com.hotkeyclash.app", category: "WorkspaceWatcher")

/// Watches apps come and go, and asks for a rescan when they do.
///
/// The results go stale the moment you quit an app: its menu shortcuts are still
/// listed as conflicting with something, and the conflict is simply gone. Before
/// this, the only cure was pressing Rescan yourself, which meant the badge count
/// was quietly wrong most of the time.
///
/// Two details make this behave rather than thrash. Apps arrive in bursts (log in
/// and a dozen launch at once, quit and a helper process follows its parent out),
/// so every notification restarts a short debounce and only the last one survives
/// to trigger a scan. And a scan is skipped outright while the panel is open,
/// because rescanning under the reader's hands rebuilds the list and throws away
/// whichever conflict they were in the middle of reading. Being a few seconds
/// stale on screen is a far smaller sin than that.
@MainActor
final class WorkspaceWatcher {

    /// How long the app churn has to settle before we scan. Long enough to absorb
    /// a login stampede, short enough that quitting one app feels answered.
    private static let debounce = Duration.seconds(4)

    private var observers: [NSObjectProtocol] = []
    private var debounceTask: Task<Void, Never>?

    /// Asked before each scan; returning false skips it. The delegate owns the
    /// reasons (setting turned off, no permission, panel open), so this type stays
    /// about noticing change rather than about policy.
    private let shouldRescan: () -> Bool
    private let onRescan: () -> Void

    init(shouldRescan: @escaping () -> Bool, onRescan: @escaping () -> Void) {
        self.shouldRescan = shouldRescan
        self.onRescan = onRescan
    }

    deinit {
        // Cannot hop to the main actor from deinit, and the center is safe to talk
        // to from anywhere, so remove the observers directly.
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
    }

    func start() {
        guard observers.isEmpty else { return }

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            let observer = center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                // The closure is delivered on the main queue, but that is a queue
                // guarantee and not an actor one, so hop explicitly.
                MainActor.assumeIsolated {
                    self?.appSetChanged(notification)
                }
            }
            observers.append(observer)
        }
        logger.debug("Watching for app launches and quits")
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil

        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
    }

    // MARK: - Reacting

    private func appSetChanged(_ notification: Notification) {
        // Our own launch is not news, and reacting to it would race the scan that
        // scanOnLaunch already kicked off.
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }

        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, let self else { return }
            guard shouldRescan() else {
                logger.debug("Skipping auto rescan: conditions not met")
                return
            }
            logger.info("App set changed, rescanning")
            onRescan()
        }
    }
}
