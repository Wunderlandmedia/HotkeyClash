import AppKit
import Foundation
import os

// nonisolated so the off-main workflow readers can log too; Logger is Sendable.
private nonisolated let logger = Logger(subsystem: "com.hotkeyclash.app", category: "AlfredScanner")

/// Reads Alfred's main hotkey and every assigned workflow hot key trigger.
///
/// The main hotkey (the one that opens Alfred's search box) isn't a workflow at
/// all. Alfred treats it as a per-Mac setting and keeps it at
/// `preferences/local/<localhash>/hotkey/prefs.plist` inside the bundle, under a
/// `default` dict with the same raw `key` keycode and Cocoa `mod` value the
/// workflows use. The catch: Alfred only writes that file once someone changes
/// the hotkey. Leave it on the out-of-the-box Alt+Space and there is no file,
/// which is exactly how we used to miss the most common Alfred shortcut of all
/// (issue #14). So no file means Alt+Space.
///
/// Alfred keeps each workflow in its own folder inside the
/// `Alfred.alfredpreferences` bundle, with an `info.plist` describing the
/// workflow's objects. A hot key trigger is the object whose
/// `type == "alfred.workflow.trigger.hotkey"`; its `config` carries a native
/// macOS virtual `hotkey` keycode and a `hotmod` bitmask that is simply the raw
/// Cocoa `NSEvent.ModifierFlags` value. That's a small gift: unlike Keyboard
/// Maestro's Carbon masks or Hammerspoon's named keys, both fields map straight
/// through with no translation table.
///
/// Two things we deliberately skip. A workflow disabled in Alfred (top-level
/// `disabled == true`) never registers its hot keys, so we drop it whole rather
/// than report shortcuts that aren't live. And a hot key trigger that hasn't
/// been assigned a shortcut yet stores `hotkey`/`hotmod` as 0 with an empty
/// `hotstring`; the non-empty `hotstring` is the reliable "actually bound"
/// signal, so we key off it and never let an unconfigured trigger masquerade as
/// a bare "A" conflict.
///
/// Powerpack users commonly sync their preferences out to Dropbox or iCloud.
/// `prefs.json` records where the bundle actually lives, so we follow that
/// pointer first and fall back to the default local folder only when it isn't
/// there. The same file holds this Mac's `localhash`.
@MainActor
final class AlfredScanner {

    private static let supportDirectory = "~/Library/Application Support/Alfred"
    private nonisolated static let bundleID = "com.runningwithcrayons.Alfred"

    /// Alfred's out-of-the-box hotkey, Alt+Space, in its own key/mod encoding.
    private nonisolated static let defaultMainKey = 49
    private nonisolated static let defaultMainMod = 1 << 19

    /// A single workflow's info.plist should never be large; anything past this
    /// is corruption, not configuration. Same spirit as the other scanners'
    /// guards. Nonisolated so the off-main reader can consult it.
    private nonisolated static let maxWorkflowBytes = 10 * 1024 * 1024

    func scan() async -> [HotkeyBinding] {
        let prefs = Self.readPrefsJSON()
        guard let bundle = Self.preferencesBundle(prefs: prefs) else {
            logger.debug("Alfred preferences bundle not found")
            return []
        }

        var bindings: [HotkeyBinding] = []
        if let main = Self.mainHotkey(bundle: bundle, localHash: prefs?["localhash"] as? String) {
            bindings.append(main)
        }

        let workflowsDir = (bundle as NSString).appendingPathComponent("workflows")
        bindings.append(contentsOf: await Self.loadAndParse(workflowsDir: workflowsDir))
        logger.info("Alfred: found \(bindings.count) hot keys")
        return bindings
    }

    // MARK: - Locating the preferences bundle

    private static func readPrefsJSON() -> [String: Any]? {
        let support = NSString(string: supportDirectory).expandingTildeInPath
        let prefsPath = (support as NSString).appendingPathComponent("prefs.json")
        guard let data = FileManager.default.contents(atPath: prefsPath) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Resolves the active `Alfred.alfredpreferences` bundle. Prefers the synced
    /// location `prefs.json` points at, then falls back to the default local
    /// bundle. Returns nil when neither exists, so a machine without Alfred
    /// simply contributes nothing.
    private static func preferencesBundle(prefs: [String: Any]?) -> String? {
        let support = NSString(string: supportDirectory).expandingTildeInPath
        var candidates: [String] = []

        // Setups in the wild disagree on whether `current` names the bundle
        // itself or the sync folder holding it, so take it either way.
        if let current = prefs?["current"] as? String, !current.isEmpty {
            let path = NSString(string: current).expandingTildeInPath
            candidates.append(path.hasSuffix(".alfredpreferences")
                ? path
                : (path as NSString).appendingPathComponent("Alfred.alfredpreferences"))
        }

        // Default local bundle.
        candidates.append((support as NSString).appendingPathComponent("Alfred.alfredpreferences"))

        let fm = FileManager.default
        for dir in candidates {
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: dir, isDirectory: &isDirectory), isDirectory.boolValue {
                return dir
            }
        }
        return nil
    }

    // MARK: - Main hotkey

    /// Reads this Mac's main hotkey file, if Alfred ever wrote one. A leftover
    /// preferences bundle from an uninstalled Alfred would otherwise claim
    /// Alt+Space forever, so the app has to actually be installed.
    private static func mainHotkey(bundle: String, localHash: String?) -> HotkeyBinding? {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else { return nil }

        var plist: Any?
        if let localHash, !localHash.isEmpty {
            let path = (bundle as NSString)
                .appendingPathComponent("preferences/local/\(localHash)/hotkey/prefs.plist")
            if let data = FileManager.default.contents(atPath: path) {
                plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
            }
        }
        return mainHotkeyBinding(fromHotkeyPrefs: plist)
    }

    // MARK: - Reading

    /// Walks every workflow folder off the main actor. Deserializing dozens of
    /// info.plists shouldn't stall the panel mid-scan.
    @concurrent
    private nonisolated static func loadAndParse(workflowsDir: String) async -> [HotkeyBinding] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: workflowsDir) else {
            logger.warning("Could not list Alfred workflows folder")
            return []
        }

        var results: [HotkeyBinding] = []
        for entry in entries {
            let plistPath = (workflowsDir as NSString)
                .appendingPathComponent(entry)
                .appending("/info.plist")
            guard fm.fileExists(atPath: plistPath) else { continue }

            if let attrs = try? fm.attributesOfItem(atPath: plistPath),
               let size = attrs[.size] as? Int, size > maxWorkflowBytes {
                logger.warning("Alfred workflow plist exceeds size limit (\(size) bytes), skipping")
                continue
            }

            guard let data = fm.contents(atPath: plistPath),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) else {
                continue
            }

            results.append(contentsOf: bindings(fromWorkflow: plist))
        }
        return results
    }

    // MARK: - Parsing

    /// Extracts hot key bindings from one workflow's decoded info.plist. Pure so
    /// tests can feed fixture dictionaries straight in without touching disk.
    ///
    /// Skips the whole workflow when it is disabled in Alfred, and skips any
    /// trigger without an assigned shortcut (empty `hotstring`). The trigger's
    /// `hotkey` is already a macOS virtual keycode and `hotmod` is the raw Cocoa
    /// modifier value, so both map straight through.
    nonisolated static func bindings(fromWorkflow plist: Any) -> [HotkeyBinding] {
        guard let workflow = plist as? [String: Any] else { return [] }
        guard workflow["disabled"] as? Bool != true else { return [] }

        let name = nonEmpty(workflow["name"] as? String)
            ?? nonEmpty(workflow["bundleid"] as? String)
            ?? "Alfred workflow"

        guard let objects = workflow["objects"] as? [[String: Any]] else { return [] }

        var results: [HotkeyBinding] = []
        for object in objects {
            guard object["type"] as? String == "alfred.workflow.trigger.hotkey",
                  let config = object["config"] as? [String: Any] else { continue }

            // An unassigned trigger leaves hotstring empty (and hotkey/hotmod 0),
            // so the non-empty hotstring is what tells us a shortcut is really set.
            guard nonEmpty(config["hotstring"] as? String) != nil else { continue }

            guard let rawKey = config["hotkey"] as? Int,
                  rawKey >= 0, rawKey <= Int(UInt16.max) else { continue }
            let hotmod = config["hotmod"] as? Int ?? 0

            results.append(HotkeyBinding(
                keyCode: UInt16(rawKey),
                modifiers: modifierFlags(fromHotmod: hotmod),
                ownerName: "Alfred",
                ownerBundleID: bundleID,
                action: name,
                source: .configFile
            ))
        }
        return results
    }

    /// Turns the decoded main hotkey prefs into a binding. Pure so tests can feed
    /// fixtures in. Nil prefs (no file) or no `default` entry means the user never
    /// changed the hotkey, so Alfred is listening on Alt+Space. A `default` entry
    /// without a usable keycode is something we don't understand, so we skip it
    /// rather than guess.
    nonisolated static func mainHotkeyBinding(fromHotkeyPrefs plist: Any?) -> HotkeyBinding? {
        var key = defaultMainKey
        var mod = defaultMainMod

        if let entry = (plist as? [String: Any])?["default"] as? [String: Any] {
            guard let rawKey = entry["key"] as? Int,
                  rawKey >= 0, rawKey <= Int(UInt16.max) else { return nil }
            key = rawKey
            mod = entry["mod"] as? Int ?? 0
        }

        return HotkeyBinding(
            keyCode: UInt16(key),
            modifiers: modifierFlags(fromHotmod: mod),
            ownerName: "Alfred",
            ownerBundleID: bundleID,
            action: "Show Alfred",
            source: .configFile
        )
    }

    /// Alfred stores `hotmod` as the raw Cocoa `NSEvent.ModifierFlags` value, so
    /// we wrap it directly and keep only the four modifiers we group conflicts by.
    nonisolated static func modifierFlags(fromHotmod hotmod: Int) -> NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(bitPattern: hotmod))
            .intersection([.command, .option, .shift, .control])
    }

    /// Trims a string to nil when it's missing or blank, so empty plist values
    /// fall through to the next fallback instead of becoming empty labels.
    private nonisolated static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}
