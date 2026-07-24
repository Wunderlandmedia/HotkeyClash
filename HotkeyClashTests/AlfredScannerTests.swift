import AppKit
import Testing
@testable import HotkeyClash

/// Tests for the Alfred workflow parsing. Fixtures mirror the real info.plist
/// shape: a workflow dict with a top-level `disabled` flag and an `objects`
/// array, where a hot key trigger carries a native virtual `hotkey` keycode and
/// a `hotmod` that is the raw Cocoa NSEvent.ModifierFlags value.
@Suite("Alfred scanner")
struct AlfredScannerTests {

    // MARK: - Fixtures

    /// Raw Cocoa modifier values, the way Alfred stores `hotmod`.
    private static let cmd = 1 << 20
    private static let shift = 1 << 17
    private static let control = 1 << 18
    private static let option = 1 << 19

    private func hotkeyTrigger(hotkey: Int, hotmod: Int, hotstring: String = "bound") -> [String: Any] {
        [
            "type": "alfred.workflow.trigger.hotkey",
            "uid": "ABCD-1234",
            "config": [
                "hotkey": hotkey,
                "hotmod": hotmod,
                "hotstring": hotstring,
                "action": 0,
                "argument": 1,
            ],
        ]
    }

    private func workflow(name: String, disabled: Bool = false, objects: [[String: Any]]) -> [String: Any] {
        ["name": name, "bundleid": "com.example.\(name)", "disabled": disabled, "objects": objects]
    }

    // MARK: - Parsing

    @Test("Assigned hot key trigger becomes a config-file binding")
    func hotkeyTriggerParses() throws {
        // Cmd+Shift+Space: keycode 49, hotmod = command + shift.
        let plist = workflow(name: "Toggle Thing", objects: [
            hotkeyTrigger(hotkey: 49, hotmod: Self.cmd + Self.shift, hotstring: "\u{21E7}\u{2318}Space"),
        ])

        let bindings = AlfredScanner.bindings(fromWorkflow: plist)
        let binding = try #require(bindings.first)
        #expect(bindings.count == 1)
        #expect(binding.keyCode == 49)
        #expect(binding.normalizedModifiers == [.command, .shift])
        #expect(binding.ownerName == "Alfred")
        #expect(binding.ownerBundleID == "com.runningwithcrayons.Alfred")
        #expect(binding.action == "Toggle Thing")
        #expect(binding.source == .configFile)
    }

    @Test("hotmod decodes as a raw Cocoa modifier value")
    func hotmodDecodes() {
        #expect(AlfredScanner.modifierFlags(fromHotmod: Self.cmd) == [.command])
        #expect(AlfredScanner.modifierFlags(fromHotmod: Self.option) == [.option])
        #expect(AlfredScanner.modifierFlags(fromHotmod: Self.control + Self.shift) == [.control, .shift])
        #expect(AlfredScanner.modifierFlags(fromHotmod: Self.cmd + Self.option + Self.control) == [.command, .option, .control])
        #expect(AlfredScanner.modifierFlags(fromHotmod: 0) == [])
    }

    @Test("Device-specific bits in hotmod are stripped")
    func deviceBitsStripped() {
        // capsLock (1 << 16) and fn (1 << 23) must not leak into the combo we group by.
        let hotmod = Self.cmd | (1 << 16) | (1 << 23)
        #expect(AlfredScanner.modifierFlags(fromHotmod: hotmod) == [.command])
    }

    @Test("Disabled workflows are skipped entirely")
    func disabledWorkflowSkipped() {
        let plist = workflow(name: "Off", disabled: true, objects: [
            hotkeyTrigger(hotkey: 49, hotmod: Self.cmd),
        ])

        #expect(AlfredScanner.bindings(fromWorkflow: plist).isEmpty)
    }

    @Test("Unassigned triggers (empty hotstring) are skipped")
    func unassignedTriggerSkipped() {
        // An untouched hotkey trigger: keycode 0, no mods, blank hotstring.
        // Reporting it would invent a phantom bare-A conflict.
        let plist = workflow(name: "Never Set", objects: [
            hotkeyTrigger(hotkey: 0, hotmod: 0, hotstring: ""),
        ])

        #expect(AlfredScanner.bindings(fromWorkflow: plist).isEmpty)
    }

    @Test("Non-hotkey objects are ignored")
    func otherObjectTypesIgnored() {
        let plist = workflow(name: "Keyword Workflow", objects: [
            ["type": "alfred.workflow.input.keyword", "uid": "X", "config": ["keyword": "foo"]],
        ])

        #expect(AlfredScanner.bindings(fromWorkflow: plist).isEmpty)
    }

    @Test("Falls back to bundle id, then a generic name, when name is blank")
    func nameFallback() throws {
        let plist: [String: Any] = [
            "name": "",
            "bundleid": "com.example.tool",
            "objects": [hotkeyTrigger(hotkey: 49, hotmod: Self.cmd)],
        ]
        let binding = try #require(AlfredScanner.bindings(fromWorkflow: plist).first)
        #expect(binding.action == "com.example.tool")

        let nameless: [String: Any] = [
            "objects": [hotkeyTrigger(hotkey: 49, hotmod: Self.cmd)],
        ]
        let fallback = try #require(AlfredScanner.bindings(fromWorkflow: nameless).first)
        #expect(fallback.action == "Alfred workflow")
    }

    @Test("Out-of-range keycodes are dropped, not trapped on")
    func outOfRangeKeyCodesDropped() {
        // A hostile or corrupt plist must not crash the UInt16 conversion.
        let plist = workflow(name: "Corrupt", objects: [
            hotkeyTrigger(hotkey: -1, hotmod: Self.cmd),
            hotkeyTrigger(hotkey: 70000, hotmod: Self.cmd),
        ])

        #expect(AlfredScanner.bindings(fromWorkflow: plist).isEmpty)
    }

    @Test("A workflow with several triggers yields several bindings")
    func multipleTriggers() {
        let plist = workflow(name: "Multi", objects: [
            hotkeyTrigger(hotkey: 49, hotmod: Self.cmd),
            hotkeyTrigger(hotkey: 45, hotmod: Self.option),
            ["type": "alfred.workflow.action.script", "config": ["script": "true"]],
        ])

        #expect(AlfredScanner.bindings(fromWorkflow: plist).count == 2)
    }

    @Test("Garbage input parses to nothing")
    func garbageInputIsEmpty() {
        #expect(AlfredScanner.bindings(fromWorkflow: "not a workflow").isEmpty)
        #expect(AlfredScanner.bindings(fromWorkflow: ["objects": "wrong type"]).isEmpty)
        #expect(AlfredScanner.bindings(fromWorkflow: 42).isEmpty)
    }
}
