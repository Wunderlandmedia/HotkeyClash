import AppKit
import os

private let logger = Logger(subsystem: "com.hotkeyclash.app", category: "MenuBarScanner")

@MainActor
final class MenuBarScanner {

    /// Hard ceiling on menu nesting depth. Real menus top out around 4-5 levels,
    /// so anything deeper indicates a corrupted or hostile AX tree and is skipped
    /// to avoid unbounded recursion.
    private nonisolated static let maxDepth = 10

    /// - Parameter includeBackgroundApps: when true, menu-bar-only / agent apps
    ///   (`.accessory`, LSUIElement) are scanned in addition to normal Dock apps.
    func scan(includeBackgroundApps: Bool) async -> [HotkeyBinding] {
        // Snapshot app identity on the main actor, where NSWorkspace and
        // NSRunningApplication are safe to touch. Tuples of Sendable values cross
        // the actor boundary cleanly.
        let targets: [Target] = NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
            switch app.activationPolicy {
            case .regular:
                // Normal Dock app.
                return Target(pid: app.processIdentifier, name: app.localizedName ?? "Unknown", bundleID: app.bundleIdentifier)
            case .accessory:
                // Menu-bar-only / agent app (e.g. Ollama). These keep their shortcuts
                // in the conventional main menu bar (kAXMenuBar), so they are scanned
                // the same way as Dock apps. The Copy/Paste noise from invisible
                // system agents (which only have the inherited default Edit menu) is
                // removed downstream by the common-shortcut filter, not here.
                guard includeBackgroundApps else { return nil }
                return Target(pid: app.processIdentifier, name: app.localizedName ?? "Unknown", bundleID: app.bundleIdentifier)
            default:
                // `.prohibited`: pure background daemon with no UI. Nothing to scan.
                return nil
            }
        }

        // Offload the cross-process AX traversal off the main actor so the UI
        // (including the "Scanning..." progress) stays responsive during the scan.
        let bindings = await Task.detached(priority: .userInitiated) {
            Self.scanTargets(targets)
        }.value
        logger.debug("Menu bar scan: \(bindings.count) shortcuts across \(targets.count) apps")
        return bindings
    }

    /// Identity + classification of one app to scan. A Sendable value type so it
    /// crosses the actor boundary into the detached traversal cleanly.
    private struct Target: Sendable {
        let pid: pid_t
        let name: String
        let bundleID: String?
    }

    /// Performs the Accessibility menu-bar traversal. Pure AX calls with no shared
    /// mutable state, so it is nonisolated and runs off the main actor.
    private nonisolated static func scanTargets(_ targets: [Target]) -> [HotkeyBinding] {
        var bindings: [HotkeyBinding] = []

        for target in targets {
            // Two distinct AX trees expose shortcuts:
            //  - kAXMenuBar: the app's main menu (File/Edit/...). Holds the real
            //    shortcuts for both Dock apps and menu-bar-only apps like Ollama.
            //  - kAXExtrasMenuBar: the app's status-bar item menu (the dropdown
            //    from its menu-bar icon).
            // Scan both for every app; downstream filtering handles the noise.
            let menuBars = [
                AccessibilityService.getMenuBar(for: target.pid),
                AccessibilityService.getExtrasMenuBar(for: target.pid),
            ].compactMap { $0 }

            for menuBar in menuBars {
                let topMenus = AccessibilityService.getChildren(of: menuBar)
                for topMenu in topMenus {
                    let topTitle = AccessibilityService.getTitle(of: topMenu) ?? ""
                    let menuItems = AccessibilityService.getChildren(of: topMenu)
                    scanMenuItems(menuItems, path: topTitle, appName: target.name, bundleID: target.bundleID, depth: 0, into: &bindings)
                }
            }
        }

        // The main and extras menu bars can surface the same item, and ConflictDetector
        // does not dedup. Drop exact duplicates (HotkeyBinding equality ignores id/source)
        // so a single app never appears to clash with itself. Order is preserved.
        var seen: Set<HotkeyBinding> = []
        return bindings.filter { seen.insert($0).inserted }
    }

    private nonisolated static func scanMenuItems(
        _ items: [AXUIElement],
        path: String,
        appName: String,
        bundleID: String?,
        depth: Int,
        into bindings: inout [HotkeyBinding]
    ) {
        guard depth < maxDepth else { return }

        for item in items {
            let title = AccessibilityService.getTitle(of: item) ?? ""
            let fullPath = path.isEmpty ? title : "\(path) > \(title)"

            // Check for keyboard shortcut on this item
            if let shortcut = AccessibilityService.getMenuItemShortcut(from: item),
               let keyCode = AccessibilityService.keyCode(for: shortcut.character) {
                let modifiers = AccessibilityService.convertAXModifiers(shortcut.modifiers)
                let binding = HotkeyBinding(
                    keyCode: keyCode,
                    modifiers: modifiers,
                    ownerName: appName,
                    ownerBundleID: bundleID,
                    action: fullPath,
                    source: .menuBar
                )
                bindings.append(binding)
            }

            // Recurse into submenus
            let children = AccessibilityService.getChildren(of: item)
            if !children.isEmpty {
                scanMenuItems(children, path: fullPath, appName: appName, bundleID: bundleID, depth: depth + 1, into: &bindings)
            }
        }
    }
}
