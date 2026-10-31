import AppKit
import Foundation
import os

// nonisolated so the off-main vault reader can log too; Logger is Sendable.
private nonisolated let logger = Logger(subsystem: "com.hotkeyclash.app", category: "ObsidianScanner")

/// Reads the custom command hotkeys from every Obsidian vault.
///
/// Obsidian keeps most of its shortcuts out of the menu bar, in the command
/// palette, so the Accessibility scan never sees them (issue #1). Each vault
/// saves the ones you customised to `<vault>/.obsidian/hotkeys.json`, a map of
/// command id to a list of `{ "modifiers": [...], "key": "J" }`. The vault list
/// itself lives in Obsidian's `obsidian.json`.
///
/// These are in-app shortcuts, not global ones: they only fire while Obsidian is
/// frontmost. So they come out as `.appConfig` on the menu item layer. Mark them
/// global and every Cmd+J that some other app also uses in its menu would turn
/// into a fake "real conflict".
///
/// Only customised hotkeys are in the file. Obsidian's defaults are not, and a
/// command whose default you removed shows up as an empty list, which we skip.
@MainActor
final class ObsidianScanner {

    private static let vaultListPath = "~/Library/Application Support/obsidian/obsidian.json"

    /// A hotkeys file is a few KB. Same corruption guard as the other scanners.
    private nonisolated static let maxFileBytes = 10 * 1024 * 1024

    func scan() async -> [HotkeyBinding] {
        let listPath = NSString(string: Self.vaultListPath).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: listPath) else {
            logger.debug("Obsidian vault list not found")
            return []
        }

        let bindings = await Self.loadAndParse(vaultListPath: listPath)
        logger.info("Obsidian: found \(bindings.count) custom hotkeys")
        return bindings
    }

    // MARK: - Reading

    /// Reads the vault list and each vault's hotkeys off the main actor. A vault
    /// in Documents or iCloud Drive can make macOS ask for folder access, and
    /// that wait should not freeze the panel.
    @concurrent
    private nonisolated static func loadAndParse(vaultListPath: String) async -> [HotkeyBinding] {
        guard let vaultList = readJSON(atPath: vaultListPath) else {
            logger.warning("Could not read Obsidian vault list")
            return []
        }

        var results: [HotkeyBinding] = []
        for vaultPath in vaultPaths(fromVaultList: vaultList) {
            let hotkeysPath = (vaultPath as NSString).appendingPathComponent(".obsidian/hotkeys.json")
            guard let hotkeys = readJSON(atPath: hotkeysPath) else { continue }
            let vaultName = (vaultPath as NSString).lastPathComponent
            results.append(contentsOf: bindings(fromHotkeys: hotkeys, vaultName: vaultName))
        }
        return results
    }

    private nonisolated static func readJSON(atPath path: String) -> Any? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return nil }
        if let attrs = try? fm.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int, size > maxFileBytes {
            logger.warning("Obsidian file exceeds size limit (\(size) bytes), skipping")
            return nil
        }
        guard let data = fm.contents(atPath: path) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    // MARK: - Parsing

    /// Vault folders from a decoded `obsidian.json`. `vaults` is keyed by a random
    /// id, so the order is meaningless; sort by path so scans stay stable.
    nonisolated static func vaultPaths(fromVaultList json: Any) -> [String] {
        guard let root = json as? [String: Any],
              let vaults = root["vaults"] as? [String: Any] else { return [] }
        return vaults.values
            .compactMap { ($0 as? [String: Any])?["path"] as? String }
            .filter { !$0.isEmpty }
            .sorted()
    }

    /// Turns one vault's decoded `hotkeys.json` into bindings. Pure so tests can
    /// feed it dictionaries without a vault on disk.
    nonisolated static func bindings(fromHotkeys json: Any, vaultName: String) -> [HotkeyBinding] {
        guard let commands = json as? [String: Any] else { return [] }

        var results: [HotkeyBinding] = []
        for (commandID, value) in commands.sorted(by: { $0.key < $1.key }) {
            // An empty list means "I removed the default", which is no shortcut.
            guard let hotkeys = value as? [[String: Any]] else { continue }
            for hotkey in hotkeys {
                guard let key = hotkey["key"] as? String,
                      let keyCode = keyCode(forObsidianKey: key) else { continue }
                let tokens = hotkey["modifiers"] as? [String] ?? []
                results.append(HotkeyBinding(
                    keyCode: keyCode,
                    modifiers: modifierFlags(fromTokens: tokens),
                    ownerName: "Obsidian",
                    ownerBundleID: "md.obsidian",
                    action: "\(commandName(fromID: commandID)) (\(vaultName) vault)",
                    source: .appConfig
                ))
            }
        }
        return results
    }

    /// Obsidian writes `Mod` for the platform's main modifier, which on a Mac is
    /// Command, and `Meta` is Command too. `Ctrl` is the real Control key.
    nonisolated static func modifierFlags(fromTokens tokens: [String]) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        for token in tokens {
            switch token.lowercased() {
            case "mod", "meta": flags.insert(.command)
            case "shift": flags.insert(.shift)
            case "alt": flags.insert(.option)
            case "ctrl": flags.insert(.control)
            default: break
            }
        }
        return flags
    }

    /// Obsidian names keys the way the browser does (`J`, `ArrowUp`, `Enter`).
    /// Single characters reuse the ANSI map the other scanners share.
    nonisolated static func keyCode(forObsidianKey key: String) -> UInt16? {
        if let named = namedKeyMap[key.lowercased()] { return named }
        guard key.count == 1 else { return nil }
        return HammerspoonScanner.characterKeyMap[key.lowercased()]
    }

    /// "editor:toggle-highlight" reads as "Editor: Toggle highlight", close to how
    /// the command palette words it. The file has no display names, so the id is
    /// all we have; keeping the prefix shows which plugin a command came from.
    nonisolated static func commandName(fromID id: String) -> String {
        let parts = id.split(separator: ":", maxSplits: 1).map { humanize(String($0)) }
        return parts.joined(separator: ": ")
    }

    private nonisolated static func humanize(_ slug: String) -> String {
        let spaced = slug.replacingOccurrences(of: "-", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    /// Browser key names for the keys that are not a single character. Unlike
    /// Hammerspoon, `Delete` here is forward delete; Backspace is the big one.
    private nonisolated static let namedKeyMap: [String: UInt16] = [
        "enter": 0x24, "tab": 0x30, " ": 0x31, "space": 0x31,
        "backspace": 0x33, "delete": 0x75, "escape": 0x35,
        "home": 0x73, "pageup": 0x74, "end": 0x77, "pagedown": 0x79,
        "arrowleft": 0x7B, "arrowright": 0x7C, "arrowdown": 0x7D, "arrowup": 0x7E,
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
        "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
        "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
    ]
}
