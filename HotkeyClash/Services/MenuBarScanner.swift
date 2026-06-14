import AppKit
import os

private let logger = Logger(subsystem: "com.hotkeyclash.app", category: "MenuBarScanner")

@MainActor
final class MenuBarScanner {

    /// Hard ceiling on menu nesting depth. Real menus top out around 4-5 levels,
    /// so anything deeper indicates a corrupted or hostile AX tree and is skipped
    /// to avoid unbounded recursion.
    private nonisolated static let maxDepth = 10

    func scan() async -> [HotkeyBinding] {
        // Snapshot app identity on the main actor, where NSWorkspace and
        // NSRunningApplication are safe to touch. Tuples of Sendable values cross
        // the actor boundary cleanly.
        let targets: [(pid: pid_t, name: String, bundleID: String?)] = NSWorkspace.shared.runningApplications
            .filter {
                $0.activationPolicy == .regular
                    && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
            }
            .map { ($0.processIdentifier, $0.localizedName ?? "Unknown", $0.bundleIdentifier) }

        // Offload the cross-process AX traversal off the main actor so the UI
        // (including the "Scanning..." progress) stays responsive during the scan.
        let bindings = await Task.detached(priority: .userInitiated) {
            Self.scanTargets(targets)
        }.value
        logger.debug("Menu bar scan: \(bindings.count) shortcuts across \(targets.count) apps")
        return bindings
    }

    /// Performs the Accessibility menu-bar traversal. Pure AX calls with no shared
    /// mutable state, so it is nonisolated and runs off the main actor.
    private nonisolated static func scanTargets(_ targets: [(pid: pid_t, name: String, bundleID: String?)]) -> [HotkeyBinding] {
        var bindings: [HotkeyBinding] = []

        for target in targets {
            guard let menuBar = AccessibilityService.getMenuBar(for: target.pid) else {
                continue
            }

            let topMenus = AccessibilityService.getChildren(of: menuBar)
            for topMenu in topMenus {
                let topTitle = AccessibilityService.getTitle(of: topMenu) ?? ""
                let menuItems = AccessibilityService.getChildren(of: topMenu)
                scanMenuItems(menuItems, path: topTitle, appName: target.name, bundleID: target.bundleID, depth: 0, into: &bindings)
            }
        }

        return bindings
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
