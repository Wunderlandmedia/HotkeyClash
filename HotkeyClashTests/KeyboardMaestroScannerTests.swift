import AppKit
import Testing
@testable import HotkeyClash

/// Tests for the Keyboard Maestro plist parsing. Fixtures mirror the real
/// library shape: MacroGroups wrapping Macros wrapping Triggers, with hot key
/// triggers carrying a virtual KeyCode and a Carbon modifier mask.
@Suite("Keyboard Maestro scanner")
struct KeyboardMaestroScannerTests {

    // MARK: - Fixtures

    private func hotKeyTrigger(keyCode: Int, modifiers: Int) -> [String: Any] {
        [
            "MacroTriggerType": "HotKey",
            "FireType": "Pressed",
            "KeyCode": keyCode,
            "Modifiers": modifiers,
        ]
    }

    private func macro(name: String, isActive: Bool = true, triggers: [[String: Any]]) -> [String: Any] {
        ["Name": name, "IsActive": isActive, "Triggers": triggers]
    }

    private func group(name: String, isActive: Bool = true, macros: [[String: Any]]) -> [String: Any] {
        ["Name": name, "IsActive": isActive, "Macros": macros]
    }

    private func library(_ groups: [[String: Any]]) -> [String: Any] {
        ["MacroGroups": groups]
    }

    // MARK: - Parsing

    @Test("Hot key trigger becomes a config-file binding")
    func hotKeyTriggerParses() throws {
        // Cmd+Shift+B: Carbon mask 256 + 512, keycode 11.
        let plist = library([group(name: "Global Macro Group", macros: [
            macro(name: "Toggle Thing", triggers: [hotKeyTrigger(keyCode: 11, modifiers: 768)]),
        ])])

        let bindings = KeyboardMaestroScanner.parse(plist)
        let binding = try #require(bindings.first)
        #expect(bindings.count == 1)
        #expect(binding.keyCode == 11)
        #expect(binding.normalizedModifiers == [.command, .shift])
        #expect(binding.ownerName == "Keyboard Maestro")
        #expect(binding.action == "Global Macro Group > Toggle Thing")
        #expect(binding.source == .configFile)
    }

    @Test("Carbon modifier masks decode to the right flags")
    func carbonMaskDecodes() {
        // cmdKey 256, shiftKey 512, optionKey 2048, controlKey 4096.
        #expect(KeyboardMaestroScanner.modifierFlags(fromCarbonMask: 256) == [.command])
        #expect(KeyboardMaestroScanner.modifierFlags(fromCarbonMask: 2048) == [.option])
        #expect(KeyboardMaestroScanner.modifierFlags(fromCarbonMask: 4096 + 512) == [.control, .shift])
        #expect(KeyboardMaestroScanner.modifierFlags(fromCarbonMask: 0) == [])
    }

    @Test("Disabled macros are skipped")
    func disabledMacroSkipped() throws {
        let plist = library([group(name: "Group", macros: [
            macro(name: "Off", isActive: false, triggers: [hotKeyTrigger(keyCode: 15, modifiers: 256)]),
            macro(name: "On", triggers: [hotKeyTrigger(keyCode: 45, modifiers: 256)]),
        ])])

        let bindings = KeyboardMaestroScanner.parse(plist)
        let binding = try #require(bindings.first)
        #expect(bindings.count == 1)
        #expect(binding.keyCode == 45)
    }

    @Test("Disabled groups are skipped entirely")
    func disabledGroupSkipped() {
        let plist = library([group(name: "Off Group", isActive: false, macros: [
            macro(name: "Would Fire", triggers: [hotKeyTrigger(keyCode: 15, modifiers: 256)]),
        ])])

        #expect(KeyboardMaestroScanner.parse(plist).isEmpty)
    }

    @Test("Non-hotkey triggers are ignored")
    func otherTriggerTypesIgnored() {
        let plist = library([group(name: "Group", macros: [
            macro(name: "Typed", triggers: [[
                "MacroTriggerType": "TypedString",
                "TypedString": "zdate",
            ]]),
        ])])

        #expect(KeyboardMaestroScanner.parse(plist).isEmpty)
    }

    @Test("Out-of-range keycodes are dropped, not trapped on")
    func outOfRangeKeyCodesDropped() {
        // A hostile or corrupt plist must not crash the UInt16 conversion.
        let plist = library([group(name: "Group", macros: [
            macro(name: "Negative", triggers: [hotKeyTrigger(keyCode: -1, modifiers: 256)]),
            macro(name: "Huge", triggers: [hotKeyTrigger(keyCode: 70000, modifiers: 256)]),
        ])])

        #expect(KeyboardMaestroScanner.parse(plist).isEmpty)
    }

    @Test("Bare group arrays (kmmacros exports) parse too")
    func bareArrayParses() throws {
        let groups = [group(name: "Exported", macros: [
            macro(name: "Macro", triggers: [hotKeyTrigger(keyCode: 49, modifiers: 256)]),
        ])]

        let bindings = KeyboardMaestroScanner.parse(groups)
        let binding = try #require(bindings.first)
        #expect(bindings.count == 1)
        #expect(binding.keyCode == 49)
        #expect(binding.normalizedModifiers == [.command])
    }

    @Test("Garbage input parses to nothing")
    func garbageInputIsEmpty() {
        #expect(KeyboardMaestroScanner.parse("not a library").isEmpty)
        #expect(KeyboardMaestroScanner.parse(["MacroGroups": "wrong type"]).isEmpty)
    }
}
