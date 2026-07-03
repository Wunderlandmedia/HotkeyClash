import AppKit
import Foundation
import SQLite3
import os

// nonisolated so the off-main store readers can log too; Logger is Sendable.
private nonisolated let logger = Logger(subsystem: "com.hotkeyclash.app", category: "BetterTouchToolScanner")

/// Reads BetterTouchTool's data store and extracts enabled keyboard shortcut triggers.
///
/// BTT persists everything in a Core Data SQLite store whose filename changes
/// with each app version (`btt_data_store.version_3_386_build_1609` and the
/// like), so we glob for the newest one rather than hardcoding a name. Every
/// trigger row in `ZBTTBASEENTITY` carries a JSON blob in `ZACTIONDATA`; that
/// JSON uses the officially documented `BTT*` field names, so we treat it as
/// the source of truth and use the version-fragile table columns only to fetch
/// it and to walk the parent chain for app scoping.
@MainActor
final class BetterTouchToolScanner {

    private static let storeDirectory = "~/Library/Application Support/BetterTouchTool"

    /// Read-size guard like the other config scanners. Preset-heavy stores get
    /// big, so this is generous; anything past it is more likely corruption
    /// than configuration.
    private static let maxStoreBytes = 100 * 1024 * 1024

    func scan() async -> [HotkeyBinding] {
        guard let storePath = Self.newestStorePath() else {
            logger.debug("BetterTouchTool data store not found")
            return []
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: storePath),
           let size = attrs[.size] as? Int, size > Self.maxStoreBytes {
            logger.warning("BetterTouchTool store exceeds size limit (\(size) bytes), skipping")
            return []
        }

        let bindings = await Self.loadBindings(fromStoreAt: storePath)
        logger.info("BetterTouchTool: found \(bindings.count) keyboard shortcuts")
        return bindings
    }

    /// Runs the store scan off the main actor: walking every trigger row and
    /// deserializing its JSON blob is exactly the kind of work that would
    /// otherwise stall the panel mid-scan.
    @concurrent
    private nonisolated static func loadBindings(fromStoreAt path: String) async -> [HotkeyBinding] {
        bindings(from: fetchRows(fromStoreAt: path))
    }

    // MARK: - Store discovery

    /// Finds the most recently modified `btt_data_store.version_*` (or legacy
    /// `.v2`) file, skipping the `-shm`/`-wal` sidecars and backup copies.
    private static func newestStorePath() -> String? {
        let dir = NSString(string: storeDirectory).expandingTildeInPath
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return nil }

        let candidates = names.filter { name in
            (name.hasPrefix("btt_data_store.version_") || name == "btt_data_store.v2")
                && !name.hasSuffix("-shm") && !name.hasSuffix("-wal")
        }

        func modificationDate(_ path: String) -> Date {
            (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date ?? .distantPast
        }

        return candidates
            .map { "\(dir)/\($0)" }
            .max { modificationDate($0) < modificationDate($1) }
    }

    // MARK: - SQLite

    /// One row of interest from the store: its primary key, its parent row, and
    /// the trigger JSON blob. A plain value type so the parsing stage below is
    /// testable without a database.
    nonisolated struct Row {
        let pk: Int64
        let parent: Int64?
        let json: Data
    }

    /// Pulls every row that carries trigger JSON. Opened read-only so we never
    /// interfere with a running BTT, and never force a WAL checkpoint.
    private nonisolated static func fetchRows(fromStoreAt path: String) -> [Row] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            logger.warning("Could not open BetterTouchTool store at \(path)")
            sqlite3_close(db)
            return []
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT Z_PK, ZPARENT, ZACTIONDATA FROM ZBTTBASEENTITY WHERE ZACTIONDATA IS NOT NULL"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            // Core Data schemas drift between BTT versions; a missing table or
            // column just means this layout is one we do not know how to read.
            logger.warning("BetterTouchTool store has an unexpected schema, skipping")
            return []
        }
        defer { sqlite3_finalize(statement) }

        var rows: [Row] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let pk = sqlite3_column_int64(statement, 0)
            let parent: Int64? = sqlite3_column_type(statement, 1) == SQLITE_NULL
                ? nil
                : sqlite3_column_int64(statement, 1)
            guard let bytes = sqlite3_column_blob(statement, 2) else { continue }
            let count = Int(sqlite3_column_bytes(statement, 2))
            rows.append(Row(pk: pk, parent: parent, json: Data(bytes: bytes, count: count)))
        }
        return rows
    }

    // MARK: - Parsing

    /// Turns fetched rows into bindings. Split out as a pure function so tests
    /// can feed synthetic rows without a real store.
    ///
    /// Keyboard shortcuts are the rows whose JSON declares
    /// `BTTTriggerClass == "BTTTriggerTypeKeyboardShortcut"`. App scoping comes
    /// from walking `ZPARENT` up to the container row that carries a
    /// `BTTAppBundleIdentifier`: `BT.G` is BTT's global container, a real bundle
    /// ID means the shortcut only fires in that app, and `BT.L` is the "Recently
    /// Used" pseudo-app. We keep global shortcuts (and unresolvable ones, since
    /// most BTT keyboard shortcuts are global) and skip app-scoped rows so they
    /// cannot masquerade as always-on conflicts.
    nonisolated static func bindings(from rows: [Row]) -> [HotkeyBinding] {
        var jsonByPK: [Int64: [String: Any]] = [:]
        var parentByPK: [Int64: Int64] = [:]
        for row in rows {
            guard let json = try? JSONSerialization.jsonObject(with: row.json) as? [String: Any] else { continue }
            jsonByPK[row.pk] = json
            if let parent = row.parent { parentByPK[row.pk] = parent }
        }

        var bindings: [HotkeyBinding] = []

        for row in rows {
            guard let json = jsonByPK[row.pk],
                  json["BTTTriggerClass"] as? String == "BTTTriggerTypeKeyboardShortcut" else { continue }

            // Both enabled flags default to on when absent; a zero in either
            // means the user switched the trigger off.
            if let enabled = json["BTTEnabled"] as? Int, enabled == 0 { continue }
            if let enabled = json["BTTEnabled2"] as? Int, enabled == 0 { continue }

            if let scope = containerBundleID(of: row.pk, jsonByPK: jsonByPK, parentByPK: parentByPK),
               scope != "BT.G" {
                continue
            }

            // Keycode -1 marks a layout-adaptive shortcut; the key then lives
            // only in BTTLayoutIndependentChar.
            var keyCode: UInt16?
            if let raw = json["BTTShortcutKeyCode"] as? Int, raw >= 0, raw <= Int(UInt16.max) {
                keyCode = UInt16(raw)
            } else if let char = json["BTTLayoutIndependentChar"] as? String {
                keyCode = Self.keyCode(forLayoutIndependentChar: char)
            }
            guard let keyCode else { continue }

            guard let rawModifiers = json["BTTShortcutModifierKeys"] as? Int, rawModifiers >= 0 else { continue }
            let modifiers = NSEvent.ModifierFlags(rawValue: UInt(rawModifiers))
                .intersection([.command, .option, .shift, .control])

            let action = (json["BTTTriggerTypeDescription"] as? String)
                ?? (json["BTTGestureNotes"] as? String)
                ?? (json["BTTPredefinedActionName"] as? String)
                ?? "BetterTouchTool trigger"

            bindings.append(HotkeyBinding(
                keyCode: keyCode,
                modifiers: modifiers,
                ownerName: "BetterTouchTool",
                ownerBundleID: "com.hegenberg.BetterTouchTool",
                action: action,
                source: .configFile
            ))
        }

        return bindings
    }

    /// Walks the parent chain until it hits a row whose JSON names an app
    /// container. Returns nil when the chain runs out without finding one.
    nonisolated private static func containerBundleID(
        of pk: Int64,
        jsonByPK: [Int64: [String: Any]],
        parentByPK: [Int64: Int64]
    ) -> String? {
        var current = parentByPK[pk]
        var hops = 0
        while let pk = current, hops < 32 {
            if let bundleID = jsonByPK[pk]?["BTTAppBundleIdentifier"] as? String {
                return bundleID
            }
            current = parentByPK[pk]
            hops += 1
        }
        return nil
    }

    /// Maps BTT's layout-independent character names back to virtual keycodes.
    /// Letters and digits come through lowercased; named keys are uppercase words.
    nonisolated static func keyCode(forLayoutIndependentChar char: String) -> UInt16? {
        switch char.uppercased() {
        case "SPACE": return 0x31
        case "RETURN", "ENTER": return 0x24
        case "TAB": return 0x30
        case "ESCAPE", "ESC": return 0x35
        case "DELETE", "BACKSPACE": return 0x33
        default: break
        }
        guard char.count == 1 else { return nil }
        return characterKeyMap[char.lowercased()]
    }

    /// ANSI layout keycodes for single characters, matching the maps the other
    /// config scanners use.
    nonisolated private static let characterKeyMap: [String: UInt16] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05,
        "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
        "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11,
        "o": 0x1F, "u": 0x20, "i": 0x22, "p": 0x23, "l": 0x25,
        "j": 0x26, "k": 0x28, "n": 0x2D, "m": 0x2E,
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17,
        "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19, "0": 0x1D,
        "-": 0x1B, "=": 0x18, "[": 0x21, "]": 0x1E,
        "\\": 0x2A, ";": 0x29, "'": 0x27,
        ",": 0x2B, ".": 0x2F, "/": 0x2C, "`": 0x32,
    ]
}
