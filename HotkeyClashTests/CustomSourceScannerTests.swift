import AppKit
import Testing
@testable import HotkeyClash

/// Tests for the user-supplied source files. The format is ours, so the fixtures
/// are the documented shape plus the ways a hand-written file goes wrong: a key
/// nobody can resolve, a layer with a typo, a file with no name. Each of those
/// must drop quietly rather than invent a shortcut or a layer.
@Suite("Custom source scanner")
struct CustomSourceScannerTests {

    // MARK: - Helpers

    private func parse(_ json: String) -> [HotkeyBinding] {
        CustomSourceScanner.bindings(from: Data(json.utf8))
    }

    // MARK: - Happy path

    @Test("A documented source file parses under its own name, bundle, and layer")
    func documentedShape() throws {
        let bindings = parse("""
        {
          "name": "Raycast",
          "bundleID": "com.raycast.macos",
          "layer": "globalHotkey",
          "bindings": [
            { "key": "space", "modifiers": ["cmd"], "action": "Open Raycast" },
            { "key": "b", "modifiers": ["ctrl", "alt", "cmd"], "action": "Bitwarden" }
          ]
        }
        """)
        #expect(bindings.count == 2)

        let launcher = try #require(bindings.first)
        #expect(launcher.keyCode == 0x31)
        #expect(launcher.normalizedModifiers == [.command])
        #expect(launcher.ownerName == "Raycast")
        #expect(launcher.ownerBundleID == "com.raycast.macos")
        #expect(launcher.action == "Open Raycast")
        #expect(launcher.source == .configFile)
        #expect(HotkeyLayer.classify(launcher) == .globalHotKey)

        let hyper = bindings[1]
        #expect(hyper.keyCode == 0x0B)
        #expect(hyper.normalizedModifiers == [.control, .option, .command])
    }

    @Test("A raw keyCode wins over a key name and needs no map")
    func rawKeyCode() throws {
        let binding = try #require(parse("""
        { "name": "Tool", "bindings": [ { "keyCode": 49, "key": "b", "modifiers": ["opt"] } ] }
        """).first)
        #expect(binding.keyCode == 49)
        #expect(binding.normalizedModifiers == [.option])
    }

    @Test("Modifier words accept the search spellings and glyphs")
    func modifierSpellings() {
        let flags = CustomSourceScanner.modifierFlags(fromTokens: ["command", "option", "SHIFT", "control", "globe"])
        #expect(flags == [.command, .option, .shift, .control, .function])
        #expect(CustomSourceScanner.modifierFlags(fromTokens: ["\u{2318}", "\u{2325}"]) == [.command, .option])
    }

    @Test("A binding with no action gets a label naming the tool")
    func defaultAction() throws {
        let binding = try #require(parse("""
        { "name": "Tool", "bindings": [ { "key": "t", "modifiers": ["cmd"] } ] }
        """).first)
        #expect(binding.action == "Tool shortcut")
    }

    // MARK: - Layers

    @Test("Every badge word maps to its layer, ignoring case and spaces")
    func layerNames() {
        #expect(HotkeyLayer.named("driver") == .driver)
        #expect(HotkeyLayer.named("eventTap") == .eventTap)
        #expect(HotkeyLayer.named("Event Tap") == .eventTap)
        #expect(HotkeyLayer.named("system") == .system)
        #expect(HotkeyLayer.named("globalHotkey") == .globalHotKey)
        #expect(HotkeyLayer.named("global") == .otherGlobal)
        #expect(HotkeyLayer.named("menuItem") == .menuItem)
        #expect(HotkeyLayer.named("kernel") == nil)
    }

    @Test("No layer, or an unknown one, lands on the catch-all rather than a guess")
    func unknownLayerIsCatchAll() throws {
        let none = try #require(parse("""
        { "name": "Tool", "bindings": [ { "key": "t", "modifiers": ["cmd"] } ] }
        """).first)
        #expect(none.declaredLayer == nil)
        #expect(HotkeyLayer.classify(none) == .otherGlobal)

        let typo = try #require(parse("""
        { "name": "Tool", "layer": "kernal", "bindings": [ { "key": "t", "modifiers": ["cmd"] } ] }
        """).first)
        #expect(HotkeyLayer.classify(typo) == .otherGlobal)
    }

    @Test("A menuItem layer makes the shortcuts in-app, not global")
    func menuItemIsInApp() throws {
        let binding = try #require(parse("""
        { "name": "Editor", "layer": "menuItem", "bindings": [ { "key": "p", "modifiers": ["cmd", "shift"] } ] }
        """).first)
        #expect(binding.source == .appConfig)
        #expect(HotkeyLayer.classify(binding) == .menuItem)
    }

    @Test("A declared layer does not disturb the built-in scanners")
    func builtInsStillClassifyByOwner() {
        let skhd = HotkeyBinding(keyCode: 0x0C, modifiers: [.command], ownerName: "skhd", action: "x", source: .configFile)
        #expect(HotkeyLayer.classify(skhd) == .eventTap)
    }

    // MARK: - Rejections

    @Test("A binding whose key does not resolve is skipped, the rest kept")
    func unresolvableKeySkipped() {
        let bindings = parse("""
        { "name": "Tool", "bindings": [
            { "key": "hyperspace", "modifiers": ["cmd"] },
            { "key": "k", "modifiers": ["cmd"] }
        ] }
        """)
        #expect(bindings.map(\.keyCode) == [0x28])
    }

    @Test("A source without a name yields nothing")
    func missingName() {
        #expect(parse(#"{ "bindings": [ { "key": "k", "modifiers": ["cmd"] } ] }"#).isEmpty)
        #expect(parse(#"{ "name": "  ", "bindings": [ { "key": "k", "modifiers": ["cmd"] } ] }"#).isEmpty)
    }

    @Test("Malformed JSON and the wrong top-level shape yield nothing")
    func malformed() {
        #expect(parse("{ not json").isEmpty)
        #expect(parse("[1, 2, 3]").isEmpty)
        #expect(parse(#"{ "name": "Tool", "bindings": "nope" }"#).isEmpty)
    }
}
