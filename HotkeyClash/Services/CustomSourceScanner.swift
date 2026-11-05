import AppKit
import Foundation
import os

// nonisolated so the off-main file reader can log too; Logger is Sendable.
private nonisolated let logger = Logger(subsystem: "com.hotkeyclash.app", category: "CustomSourceScanner")

/// Reads shortcut lists the user wrote (or generated) themselves from
/// `~/.config/hotkeyclash/sources/*.json`.
///
/// Some tools keep their shortcuts where no static parser can follow: Raycast's
/// store is encrypted, a tiling window manager may hold its chords only in
/// memory, a corporate launcher may have no config at all. HotkeyClash cannot
/// read those, but the user often can, with a script, an export, or by hand. A
/// custom source lets them hand that list over under the tool's own name and
/// layer, so the conflict list and the likely-winner hint stay honest instead of
/// those shortcuts being invisible or smuggled in as some other tool's.
///
/// One file per tool. The shape is deliberately flat:
///
/// ```json
/// {
///   "name": "Raycast",
///   "bundleID": "com.raycast.macos",
///   "layer": "globalHotkey",
///   "bindings": [
///     { "key": "space", "modifiers": ["cmd"], "action": "Open Raycast" },
///     { "keyCode": 11, "modifiers": ["ctrl", "alt", "cmd"], "action": "Bitwarden" }
///   ]
/// }
/// ```
///
/// `name` is required. `bundleID` is optional and only fetches the icon.
/// `layer` is optional and takes the badge words from the detail pane
/// (`driver`, `eventTap`, `system`, `globalHotkey`, `global`, `menuItem`); a
/// missing or unknown layer lands on the catch-all, and `menuItem` makes the
/// shortcuts in-app rather than global, like Obsidian's. Each binding names its
/// key either by `key` (the names Hammerspoon uses: letters, digits, `space`,
/// `return`, `left`, `f5`, `pad5`) or by a raw `keyCode`, and lists `modifiers`
/// as words (`cmd`, `opt`/`alt`, `shift`, `ctrl`, `fn`/`globe`).
@MainActor
final class CustomSourceScanner {

    private static let sourcesDirectory = "~/.config/hotkeyclash/sources"

    /// A generated list of a few hundred shortcuts is tens of KB. Same corruption
    /// guard as the other scanners.
    private nonisolated static let maxFileBytes = 10 * 1024 * 1024

    func scan() async -> [HotkeyBinding] {
        let dir = NSString(string: Self.sourcesDirectory).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: dir) else {
            logger.debug("Custom sources directory not found")
            return []
        }

        let bindings = await Self.loadAndParse(directory: dir)
        logger.info("Custom sources: found \(bindings.count) shortcuts")
        return bindings
    }

    // MARK: - Reading

    /// Reads every source file off the main actor. The files are small, but the
    /// directory could sit on a network volume, and that wait should not freeze
    /// the panel.
    @concurrent
    private nonisolated static func loadAndParse(directory: String) async -> [HotkeyBinding] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory) else {
            logger.warning("Could not list custom sources directory")
            return []
        }

        var results: [HotkeyBinding] = []
        for name in names.filter({ $0.hasSuffix(".json") }).sorted() {
            let path = (directory as NSString).appendingPathComponent(name)
            if let attrs = try? fm.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int, size > maxFileBytes {
                logger.warning("Custom source exceeds size limit (\(size) bytes), skipping")
                continue
            }
            guard let data = fm.contents(atPath: path) else {
                logger.warning("Could not read a custom source file")
                continue
            }
            let parsed = bindings(from: data)
            if parsed.isEmpty {
                logger.warning("Custom source yielded no shortcuts; check its name, keys, and layer")
            }
            results.append(contentsOf: parsed)
        }
        return results
    }

    // MARK: - Parsing

    /// Turns one source file's bytes into bindings. Pure so tests can feed JSON
    /// straight in without touching disk. Malformed JSON, a missing name, or a
    /// binding whose key does not resolve all yield nothing rather than a guess.
    nonisolated static func bindings(from data: Data) -> [HotkeyBinding] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return bindings(fromSource: json)
    }

    nonisolated static func bindings(fromSource json: [String: Any]) -> [HotkeyBinding] {
        guard let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespaces),
              !name.isEmpty,
              let entries = json["bindings"] as? [[String: Any]] else { return [] }

        let bundleID = (json["bundleID"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let layer = (json["layer"] as? String).flatMap(HotkeyLayer.named)

        // An in-app source only fires while its app is frontmost, which is what
        // `.appConfig` means to the conflict classifier. Everything else is global.
        let source: HotkeyBinding.BindingSource = layer == .menuItem ? .appConfig : .configFile

        var results: [HotkeyBinding] = []
        for entry in entries {
            guard let keyCode = keyCode(from: entry) else { continue }
            let tokens = entry["modifiers"] as? [String] ?? []
            let action = (entry["action"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "\(name) shortcut"
            results.append(HotkeyBinding(
                keyCode: keyCode,
                modifiers: modifierFlags(fromTokens: tokens),
                ownerName: name,
                ownerBundleID: bundleID,
                action: action,
                source: source,
                declaredLayer: source == .configFile ? layer : nil
            ))
        }
        return results
    }

    /// `keyCode` wins when both are present, since it is the less ambiguous of
    /// the two. `key` goes through the Hammerspoon names, which the other
    /// text-based scanners already share.
    nonisolated static func keyCode(from entry: [String: Any]) -> UInt16? {
        if let raw = entry["keyCode"] as? Int, raw >= 0, raw <= Int(UInt16.max) {
            return UInt16(raw)
        }
        if let key = entry["key"] as? String {
            return HammerspoonScanner.keyCode(forHammerspoonKey: key)
        }
        return nil
    }

    /// The modifier words `ComboLookup` accepts in a search, plus Hammerspoon's
    /// spellings, so a file can use whichever the user already thinks in.
    nonisolated static func modifierFlags(fromTokens tokens: [String]) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        for token in tokens {
            switch token.lowercased() {
            case "cmd", "command", "\u{2318}": flags.insert(.command)
            case "opt", "option", "alt", "\u{2325}": flags.insert(.option)
            case "shift", "\u{21E7}": flags.insert(.shift)
            case "ctrl", "control", "\u{2303}": flags.insert(.control)
            case "fn", "globe", "function": flags.insert(.function)
            default: break
            }
        }
        return flags
    }
}
