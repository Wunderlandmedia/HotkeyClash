import AppKit
import Testing
@testable import HotkeyClash

/// Tests for the Obsidian vault parsing. Fixtures mirror the real files: a
/// `vaults` dict keyed by random ids in `obsidian.json`, and a command id to
/// hotkey-list map in each vault's `hotkeys.json`.
@Suite("Obsidian scanner", .bug(id: 1))
struct ObsidianScannerTests {

    @Test("A custom hotkey becomes an in-app Obsidian binding")
    func customHotkey() throws {
        let json: [String: Any] = ["editor:toggle-highlight": [["modifiers": ["Mod"], "key": "j"]]]
        let binding = try #require(ObsidianScanner.bindings(fromHotkeys: json, vaultName: "Books").first)

        #expect(binding.keyCode == 0x26)
        #expect(binding.modifiers == [.command])
        #expect(binding.ownerName == "Obsidian")
        #expect(binding.ownerBundleID == "md.obsidian")
        #expect(binding.action == "Editor: Toggle highlight (Books vault)")
        #expect(binding.source == .appConfig)
    }

    @Test("Removed defaults are skipped, multiple bindings are all kept")
    func emptyAndMultiple() {
        let json: [String: Any] = [
            "app:go-back": [Any](),
            "workspace:split-vertical": [
                ["modifiers": ["Mod", "Shift"], "key": "ArrowRight"],
                ["modifiers": ["Ctrl", "Alt"], "key": "\\"],
            ],
        ]
        let bindings = ObsidianScanner.bindings(fromHotkeys: json, vaultName: "Notes")

        #expect(bindings.count == 2)
        #expect(bindings[0].keyCode == 0x7C)
        #expect(bindings[0].modifiers == [.command, .shift])
        #expect(bindings[1].keyCode == 0x2A)
        #expect(bindings[1].modifiers == [.control, .option])
    }

    @Test("Mod and Meta are both Command, Ctrl is Control")
    func modifiers() {
        #expect(ObsidianScanner.modifierFlags(fromTokens: ["Mod"]) == [.command])
        #expect(ObsidianScanner.modifierFlags(fromTokens: ["Meta"]) == [.command])
        #expect(ObsidianScanner.modifierFlags(fromTokens: ["Ctrl", "Shift", "Alt"]) == [.control, .shift, .option])
    }

    @Test("Browser key names map to keycodes", arguments: [
        ("J", UInt16(0x26)), (",", 0x2B), ("ArrowUp", 0x7E), ("Enter", 0x24),
        ("Backspace", 0x33), ("Delete", 0x75), ("F5", 0x60), (" ", 0x31),
    ])
    func keyNames(key: String, expected: UInt16) {
        #expect(ObsidianScanner.keyCode(forObsidianKey: key) == expected)
    }

    @Test("Unknown keys are dropped rather than guessed")
    func unknownKey() {
        #expect(ObsidianScanner.keyCode(forObsidianKey: "MediaPlayPause") == nil)
        let json: [String: Any] = ["x:y": [["modifiers": ["Mod"], "key": "MediaPlayPause"]]]
        #expect(ObsidianScanner.bindings(fromHotkeys: json, vaultName: "V").isEmpty)
    }

    @Test("Vault paths come from the vaults dict, sorted")
    func vaultList() {
        let json: [String: Any] = ["vaults": [
            "b1": ["path": "/Users/me/Zettel", "ts": 1, "open": true],
            "a2": ["path": "/Users/me/Books", "ts": 2],
            "c3": ["ts": 3],
        ]]
        #expect(ObsidianScanner.vaultPaths(fromVaultList: json) == ["/Users/me/Books", "/Users/me/Zettel"])
    }

    @Test("Plugin commands keep their plugin name")
    func commandNames() {
        #expect(ObsidianScanner.commandName(fromID: "obsidian-git:push") == "Obsidian git: Push")
        #expect(ObsidianScanner.commandName(fromID: "noprefix") == "Noprefix")
    }

    @Test("An Obsidian hotkey sits on the menu item layer and is never global")
    func notGlobal() {
        let obsidian = HotkeyBinding(keyCode: 0x26, modifiers: [.command], ownerName: "Obsidian", ownerBundleID: "md.obsidian", action: "Toggle", source: .appConfig)
        let menu = HotkeyBinding(keyCode: 0x26, modifiers: [.command], ownerName: "Safari", action: "Jump", source: .menuBar)
        let karabiner = HotkeyBinding(keyCode: 0x26, modifiers: [.command], ownerName: "Karabiner-Elements", ownerBundleID: "org.pqrs.Karabiner-Elements", action: "Rule", source: .configFile)

        #expect(HotkeyLayer.classify(obsidian) == .menuItem)
        #expect(Conflict(keyCode: 0x26, modifiers: [.command], bindings: [obsidian, menu]).category == .appOverlap)
        #expect(Conflict(keyCode: 0x26, modifiers: [.command], bindings: [obsidian, karabiner]).category == .realConflict)
    }
}
