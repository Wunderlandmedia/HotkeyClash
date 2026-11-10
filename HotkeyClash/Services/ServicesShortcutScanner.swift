import AppKit
import os

private nonisolated let logger = Logger(subsystem: "com.hotkeyclash.app", category: "ServicesShortcutScanner")

/// Reads the keyboard shortcuts on macOS Services, the entries under
/// System Settings > Keyboard > Keyboard Shortcuts > Services (issue #12).
///
/// These never show up in `com.apple.symbolichotkeys`, which is why the system
/// scan missed Terminal's Cmd-Shift-M and Cmd-Shift-A for so long. Two files
/// hold the whole story:
///
/// - `com.apple.ServicesMenu.Services` is the list `pbs` builds from every
///   installed app's `NSServices` and hands to AppKit for the Services menu.
///   Each entry carries the shortcut the app ships with.
/// - `pbs` keeps the user's edits in `NSServicesStatus`: a service switched off,
///   or given a different shortcut, keyed by "bundle id - menu title - message".
///
/// A Services shortcut only fires inside a Cocoa app, and only when that app's
/// own menus did not claim the key first, so it sits on the menu item layer
/// rather than the global ones.
@MainActor
final class ServicesShortcutScanner {

    func scan() -> [HotkeyBinding] {
        guard let vended = UserDefaults(suiteName: "com.apple.ServicesMenu.Services")?
            .dictionary(forKey: "NSServices")?["CFVendedServices"] as? [[String: Any]] else {
            logger.warning("Could not read the Services list")
            return []
        }
        let status = UserDefaults(suiteName: "pbs")?.dictionary(forKey: "NSServicesStatus") ?? [:]

        let bindings = Self.bindings(fromVended: vended, status: status)
        logger.info("Services: found \(bindings.count) shortcuts")
        return bindings
    }

    // MARK: - Parsing

    /// Turns the vended list plus the user's overrides into bindings. Pure so the
    /// tests can feed it dictionaries shaped like the real plists.
    nonisolated static func bindings(fromVended vended: [[String: Any]], status: [String: Any]) -> [HotkeyBinding] {
        var results: [HotkeyBinding] = []
        for service in vended {
            guard let menuItem = (service["NSMenuItem"] as? [String: String])?["default"],
                  let message = service["NSMessage"] as? String else { continue }
            let bundleID = service["NSBundleIdentifier"] as? String
            let key = statusKey(bundleID: bundleID, menuItem: menuItem, message: message)
            let override = status[key] as? [String: Any]
            guard isEnabled(override: override, defaultOn: !defaultOff.contains(key)) else { continue }

            // The user's own shortcut spells out every modifier. The one the app
            // ships with always implies Command, which is how NSServices defines it.
            let combo: (keyCode: UInt16, modifiers: NSEvent.ModifierFlags)?
            if let custom = override?["key_equivalent"] as? String {
                combo = parseKeyEquivalent(custom, impliesCommand: false)
            } else if let shipped = (service["NSKeyEquivalent"] as? [String: String])?["default"] {
                combo = parseKeyEquivalent(shipped, impliesCommand: true)
            } else {
                combo = nil
            }
            guard let combo else { continue }

            results.append(HotkeyBinding(
                keyCode: combo.keyCode,
                modifiers: combo.modifiers,
                ownerName: ownerName(bundlePath: service["NSBundlePath"] as? String, bundleID: bundleID),
                ownerBundleID: bundleID,
                action: displayTitle(menuItem: service["NSMenuItem"] as? [String: String] ?? [:]),
                source: .service
            ))
        }
        return results
    }

    /// How `pbs` names a service in `NSServicesStatus`. Automator workflows have
    /// no bundle id, and `pbs` writes that as a literal "(null)".
    nonisolated static func statusKey(bundleID: String?, menuItem: String, message: String) -> String {
        "\(bundleID ?? "(null)") - \(menuItem) - \(message)"
    }

    /// The Services menu checkbox is what decides whether the shortcut fires.
    /// Newer macOS writes it under `presentation_modes`, older releases as
    /// `enabled_services_menu`; with neither, the service is in its default state.
    nonisolated static func isEnabled(override: [String: Any]?, defaultOn: Bool) -> Bool {
        if let modes = override?["presentation_modes"] as? [String: Any],
           let servicesMenu = modes["ServicesMenu"] as? Bool {
            return servicesMenu
        }
        if let enabled = override?["enabled_services_menu"] as? Bool {
            return enabled
        }
        return defaultOn
    }

    /// Reads an NSMenu-style key equivalent: modifier glyphs first (`@` Command,
    /// `~` Option, `^` Control, `$` Shift), then the key. An uppercase letter
    /// means Shift as well, so Terminal's plain "M" is Cmd-Shift-M. An empty
    /// string is a shortcut the user cleared, and a key we cannot place is
    /// skipped rather than guessed.
    nonisolated static func parseKeyEquivalent(_ raw: String, impliesCommand: Bool) -> (keyCode: UInt16, modifiers: NSEvent.ModifierFlags)? {
        var modifiers: NSEvent.ModifierFlags = impliesCommand ? [.command] : []
        var rest = Substring(raw)
        while let first = rest.first, rest.count > 1 {
            switch first {
            case "@": modifiers.insert(.command)
            case "~": modifiers.insert(.option)
            case "^": modifiers.insert(.control)
            case "$": modifiers.insert(.shift)
            default: return nil
            }
            rest = rest.dropFirst()
        }
        guard rest.count == 1, let key = rest.first else { return nil }
        if key.isUppercase { modifiers.insert(.shift) }
        guard let keyCode = HammerspoonScanner.characterKeyMap[key.lowercased()] else { return nil }
        return (keyCode, modifiers)
    }

    /// The menu title as the Services menu shows it. Submenu paths like
    /// "Script Editor/Get Result of AppleScript" keep only the last part, and the
    /// user's language wins over the default when the app ships one. Safari's
    /// title carries a `%WebSearchProvider@` placeholder that AppKit fills with
    /// the search engine at menu time; we cannot, so it reads "Web Search Provider".
    nonisolated static func displayTitle(menuItem: [String: String]) -> String {
        let localized = Locale.preferredLanguages.lazy.compactMap { menuItem[$0] }.first
        let title = localized ?? menuItem["default"] ?? ""
        let leaf = title.split(separator: "/").last.map(String.init) ?? title
        return leaf.replacing(/%(\w+)@/) { match in
            String(match.1).replacing(/([a-z])([A-Z])/) { "\($0.1) \($0.2)" }
        }
    }

    /// The app (or workflow) that provides the service, named the way Finder
    /// shows it.
    nonisolated static func ownerName(bundlePath: String?, bundleID: String?) -> String {
        guard let bundlePath else { return bundleID ?? "Services" }
        return (FileManager.default.displayName(atPath: bundlePath) as NSString).deletingPathExtension
    }

    /// Services that come with a shortcut but start switched off. Nothing on disk
    /// records the default state, so this is what System Settings shows on a Mac
    /// with no Services changes (macOS 26.1). Spotlight's never even appears
    /// there or in the Services menu.
    private nonisolated static let defaultOff: Set<String> = [
        "com.apple.ScriptEditor2 - Script Editor/Get Result of AppleScript - runAsAppleScript",
        "com.apple.BluetoothFileExchange - Send File To Bluetooth Device - sendFileUsingBluetoothOBEXService",
        "com.apple.SpotlightService - SEARCH_WITH_SPOTLIGHT - doSearchWithSpotlight",
    ]
}
