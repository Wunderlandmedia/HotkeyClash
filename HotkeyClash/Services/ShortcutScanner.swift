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

    var conflictCount: Int { conflicts.count }
    var definiteConflictCount: Int { conflicts.filter { $0.severity == .definite }.count }

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
        state = .scanning(progress: "Scanning system shortcuts...")
        let start = Date()

        // 1. System shortcuts (fast, no AX needed)
        let systemBindings = systemShortcutScanner.scan()

        // 2. Config files (fast, no AX needed)
        state = .scanning(progress: "Reading config files...")
        let configBindings = configFileScanner.scan()

        // 3. Menu bar shortcuts (needs AX, runs off the main actor)
        state = .scanning(progress: "Scanning running apps...")
        let menuBindings = await menuBarScanner.scan()

        // 4. Combine and detect conflicts
        allBindings = systemBindings + configBindings + menuBindings
        conflicts = ConflictDetector.detect(bindings: allBindings)
        scanDuration = Date().timeIntervalSince(start)

        state = .completed
        logger.info("Scan complete: \(self.allBindings.count) bindings, \(self.conflicts.count) conflicts in \(String(format: "%.1f", self.scanDuration))s")
    }
}
