import AppKit
import Observation
import os

private let logger = Logger(subsystem: "com.hotkeyclash.app", category: "ShortcutScanner")

@MainActor
@Observable
final class ShortcutScanner {

    enum ScanState {
        case idle
        case scanning(progress: String)
        case completed
        case error(String)

        // Manual Equatable since associated values prevent auto-synthesis,
        // and nonisolated is required under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor.
        nonisolated static func == (lhs: ScanState, rhs: ScanState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): true
            case (.completed, .completed): true
            case (.scanning(let a), .scanning(let b)): a == b
            case (.error(let a), .error(let b)): a == b
            default: false
            }
        }
    }

    private(set) var state: ScanState = .idle
    private(set) var conflicts: [Conflict] = []
    private(set) var allBindings: [HotkeyBinding] = []
    private(set) var scanDuration: TimeInterval = 0

    private let menuBarScanner = MenuBarScanner()
    private let configFileScanner = ConfigFileScanner()
    private let systemShortcutScanner = SystemShortcutScanner()

    /// Number of always-on clashes (involve a global hotkey). The actionable count,
    /// used for the summary verdict and the menu bar badge.
    var realConflictCount: Int { conflicts.lazy.filter { $0.category == .realConflict }.count }

    /// Number of focus-dependent app menu overlaps (no global source involved).
    var appOverlapCount: Int { conflicts.count - realConflictCount }

    /// The single display list. Real conflicts pin to the top (definite first, then
    /// most clashes); app overlaps follow, ranked by how distinctive they are: a combo
    /// shared by few apps is interesting and ranks high, while universal boilerplate
    /// (Cmd+C across everything) sinks to the bottom.
    var rankedConflicts: [Conflict] {
        conflicts.sorted { lhs, rhs in
            if lhs.category != rhs.category {
                return lhs.category == .realConflict
            }
            switch lhs.category {
            case .realConflict:
                if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
                return lhs.bindings.count > rhs.bindings.count
            case .appOverlap:
                if lhs.appCount != rhs.appCount { return lhs.appCount < rhs.appCount }
                return lhs.displayString < rhs.displayString
            }
        }
    }

    private var isScanning = false

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        await runScan()
    }

    func rescan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        conflicts = []
        allBindings = []
        await runScan()
    }

    private func runScan() async {
        let settings = SettingsManager.shared
        let scanRunningApps = settings.scanRunningApps
        let scanConfigFiles = settings.scanConfigFiles
        let scanSystemShortcuts = settings.scanSystemShortcuts
        let includeBackgroundApps = settings.includeBackgroundApps

        guard scanRunningApps || scanConfigFiles || scanSystemShortcuts else {
            state = .error("All scan sources are turned off. Enable at least one in Settings, then scan again.")
            return
        }

        // App menu shortcuts require Accessibility. Without it the menu bar scan
        // silently returns nothing, so refuse to run a misleading partial scan and
        // surface the permission gap instead. Only gate on it when that source is on.
        if scanRunningApps {
            guard AccessibilityService.checkPermission() else {
                state = .error("Accessibility permission is required to scan app menu shortcuts. Grant it in System Settings, then scan again.")
                return
            }
        }

        let start = Date()
        var bindings: [HotkeyBinding] = []

        // 1. System shortcuts (fast, no AX needed)
        if scanSystemShortcuts {
            state = .scanning(progress: "Scanning system shortcuts...")
            bindings += systemShortcutScanner.scan()
        }

        // 2. Config files (fast, no AX needed)
        if scanConfigFiles {
            state = .scanning(progress: "Reading config files...")
            bindings += configFileScanner.scan()
        }

        // 3. Menu bar shortcuts (needs AX, runs off the main actor)
        if scanRunningApps {
            state = .scanning(progress: "Scanning running apps...")
            bindings += await menuBarScanner.scan(includeBackgroundApps: includeBackgroundApps)
        }

        // 4. Combine and detect conflicts
        allBindings = bindings
        conflicts = ConflictDetector.detect(bindings: allBindings)
        scanDuration = Date().timeIntervalSince(start)

        state = .completed
        logger.info("Scan complete: \(self.allBindings.count) bindings, \(self.conflicts.count) conflicts in \(String(format: "%.1f", self.scanDuration))s")
    }
}
