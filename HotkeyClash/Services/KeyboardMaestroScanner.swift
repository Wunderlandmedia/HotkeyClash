import AppKit
import Carbon
import Foundation
import os

// nonisolated so the off-main parsing helper can log too; Logger is Sendable.
private nonisolated let logger = Logger(subsystem: "com.hotkeyclash.app", category: "KeyboardMaestroScanner")

/// Reads Keyboard Maestro's macro library and extracts every enabled hot key trigger.
///
/// The library lives in `Keyboard Maestro Macros.plist`: a dictionary whose
/// `MacroGroups` array nests groups, then macros, then triggers. A hot key
/// trigger is the dict with `MacroTriggerType == "HotKey"`, carrying a macOS
/// virtual `KeyCode` and a Carbon-mask `Modifiers` field (cmdKey = 256 and
/// friends, the same masks `RegisterEventHotKey` takes). We only read the file;
/// writing it while KM runs is explicitly unsupported by its developer.
@MainActor
final class KeyboardMaestroScanner {

    private static let configPath =
        "~/Library/Application Support/Keyboard Maestro/Keyboard Maestro Macros.plist"

    /// Read-size guard like the other config scanners, but more generous:
    /// a well-used macro library grows far past what a hand-written text
    /// config ever would.
    private static let maxConfigBytes = 50 * 1024 * 1024

    func scan() async -> [HotkeyBinding] {
        let path = NSString(string: Self.configPath).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else {
            logger.debug("Keyboard Maestro library not found at \(path)")
            return []
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int, size > Self.maxConfigBytes {
            logger.warning("Keyboard Maestro library exceeds size limit (\(size) bytes), skipping")
            return []
        }

        let bindings = await Self.loadAndParse(path: path)
        logger.info("Keyboard Maestro: found \(bindings.count) hot key triggers")
        return bindings
    }

    /// Reads and parses the library off the main actor. A big macro library can
    /// take real time to deserialize, and doing that inline would freeze the
    /// panel before the "Reading config files" progress text even renders.
    @concurrent
    private nonisolated static func loadAndParse(path: String) async -> [HotkeyBinding] {
        guard let data = FileManager.default.contents(atPath: path) else {
            logger.warning("Could not read Keyboard Maestro library")
            return []
        }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) else {
            logger.warning("Could not parse Keyboard Maestro library plist")
            return []
        }
        return parse(plist)
    }

    /// Extracts hot key bindings from the decoded plist. Split out as a pure
    /// function so tests can feed fixture plists without touching disk.
    ///
    /// Accepts both the on-disk shape (dict with `MacroGroups`) and the bare
    /// group array that `.kmmacros` exports use, since they share the group schema.
    /// Disabled groups and macros are skipped: KM only registers a hot key when
    /// both the macro and its group have `IsActive` true. Groups targeted at
    /// specific apps still count; their hot keys are registered globally whenever
    /// that app runs, which is exactly the kind of surprise this app exists to show.
    nonisolated static func parse(_ plist: Any) -> [HotkeyBinding] {
        let groups: [[String: Any]]
        if let dict = plist as? [String: Any],
           let macroGroups = dict["MacroGroups"] as? [[String: Any]] {
            groups = macroGroups
        } else if let array = plist as? [[String: Any]] {
            groups = array
        } else {
            return []
        }

        var bindings: [HotkeyBinding] = []

        for group in groups {
            guard group["IsActive"] as? Bool != false else { continue }
            let groupName = group["Name"] as? String
            guard let macros = group["Macros"] as? [[String: Any]] else { continue }

            for macro in macros {
                guard macro["IsActive"] as? Bool != false else { continue }
                let macroName = macro["Name"] as? String ?? "Keyboard Maestro macro"
                guard let triggers = macro["Triggers"] as? [[String: Any]] else { continue }

                for trigger in triggers {
                    guard trigger["MacroTriggerType"] as? String == "HotKey",
                          let keyCode = trigger["KeyCode"] as? Int,
                          keyCode >= 0, keyCode <= Int(UInt16.max) else { continue }

                    let carbonMask = trigger["Modifiers"] as? Int ?? 0
                    let action: String
                    if let groupName, !groupName.isEmpty {
                        action = "\(groupName) > \(macroName)"
                    } else {
                        action = macroName
                    }

                    bindings.append(HotkeyBinding(
                        keyCode: UInt16(keyCode),
                        modifiers: modifierFlags(fromCarbonMask: carbonMask),
                        ownerName: "Keyboard Maestro",
                        ownerBundleID: "com.stairways.keyboardmaestro.engine",
                        action: action,
                        source: .configFile
                    ))
                }
            }
        }

        return bindings
    }

    /// Converts a Carbon modifier mask (as stored in the KM plist) to NSEvent flags.
    /// The inverse of `ShortcutFormatter.carbonModifiers(from:)`.
    nonisolated static func modifierFlags(fromCarbonMask mask: Int) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if mask & cmdKey != 0 { flags.insert(.command) }
        if mask & shiftKey != 0 { flags.insert(.shift) }
        if mask & optionKey != 0 { flags.insert(.option) }
        if mask & controlKey != 0 { flags.insert(.control) }
        return flags
    }
}
