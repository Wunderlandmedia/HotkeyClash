import AppKit
import Testing
@testable import HotkeyClash

/// Tests for the Hammerspoon `init.lua` parsing. Because the config is Lua
/// source rather than a structured file, the fixtures here are little snippets of
/// real-looking config: the point is that we resolve the literal binds, skip the
/// ones that hide behind variables, and never trip over comments.
@Suite("Hammerspoon scanner")
struct HammerspoonScannerTests {

    // MARK: - Happy path

    @Test("Table mods with a character key parses")
    func tableModsCharacterKey() throws {
        let source = #"hs.hotkey.bind({"cmd", "alt"}, "W", function() end)"#
        let binding = try #require(HammerspoonScanner.parse(source).first)
        #expect(binding.keyCode == 0x0D) // W
        #expect(binding.normalizedModifiers == [.command, .option])
        #expect(binding.ownerName == "Hammerspoon")
        #expect(binding.ownerBundleID == "org.hammerspoon.Hammerspoon")
        #expect(binding.source == .configFile)
    }

    @Test("A message string becomes the action label")
    func messageBecomesAction() throws {
        let source = #"hs.hotkey.bind({"cmd"}, "R", "Reload config", function() end)"#
        let binding = try #require(HammerspoonScanner.parse(source).first)
        #expect(binding.keyCode == 0x0F) // R
        #expect(binding.action == "Reload config")
    }

    @Test("Bindings without a message fall back to a generic label")
    func noMessageGenericAction() throws {
        let source = #"hs.hotkey.bind({"cmd"}, "R", function() end)"#
        let binding = try #require(HammerspoonScanner.parse(source).first)
        #expect(binding.action == "Hammerspoon hotkey")
    }

    @Test("Named keys resolve through the Hammerspoon key map")
    func namedKeysResolve() {
        #expect(HammerspoonScanner.keyCode(forHammerspoonKey: "return") == 0x24)
        #expect(HammerspoonScanner.keyCode(forHammerspoonKey: "space") == 0x31)
        #expect(HammerspoonScanner.keyCode(forHammerspoonKey: "F1") == 0x7A)
        #expect(HammerspoonScanner.keyCode(forHammerspoonKey: "left") == 0x7B)
        #expect(HammerspoonScanner.keyCode(forHammerspoonKey: "pad5") == 0x57)
    }

    @Test("Empty modifier table means a bare key, not an unresolved bind")
    func emptyModsTable() throws {
        let source = #"hs.hotkey.bind({}, "f5", function() end)"#
        let binding = try #require(HammerspoonScanner.parse(source).first)
        #expect(binding.keyCode == 0x60) // f5
        #expect(binding.normalizedModifiers == [])
    }

    @Test("A numeric keycode argument is taken as-is")
    func numericKeyCode() throws {
        let source = #"hs.hotkey.bind({"ctrl"}, 49, function() end)"#
        let binding = try #require(HammerspoonScanner.parse(source).first)
        #expect(binding.keyCode == 49)
        #expect(binding.normalizedModifiers == [.control])
    }

    // MARK: - Modifier spellings

    @Test("Modifier tokens accept Hammerspoon's spellings and glyphs")
    func modifierSpellings() {
        #expect(HammerspoonScanner.modifierFlags(fromToken: "command") == [.command])
        #expect(HammerspoonScanner.modifierFlags(fromToken: "option") == [.option])
        #expect(HammerspoonScanner.modifierFlags(fromToken: "control") == [.control])
        #expect(HammerspoonScanner.modifierFlags(fromToken: "\u{2318}") == [.command])
        #expect(HammerspoonScanner.modifierFlags(fromToken: "fn") == [])
    }

    @Test("A string mods argument can pack several modifiers")
    func combinedStringMods() throws {
        let source = #"hs.hotkey.bind("cmd-alt-ctrl", "T", function() end)"#
        let binding = try #require(HammerspoonScanner.parse(source).first)
        #expect(binding.normalizedModifiers == [.command, .option, .control])
    }

    // MARK: - Things we must skip

    @Test("Binds whose mods come from a variable are skipped")
    func variableModsSkipped() {
        let source = """
        local hyper = {"cmd", "alt", "ctrl", "shift"}
        hs.hotkey.bind(hyper, "H", function() end)
        """
        #expect(HammerspoonScanner.parse(source).isEmpty)
    }

    @Test("A table mixing a literal with a variable is treated as unresolvable")
    func mixedTableSkipped() {
        let source = #"hs.hotkey.bind({mods, "shift"}, "H", function() end)"#
        #expect(HammerspoonScanner.parse(source).isEmpty)
    }

    @Test("Binds whose key comes from a variable are skipped")
    func variableKeySkipped() {
        let source = #"hs.hotkey.bind({"cmd"}, someKey, function() end)"#
        #expect(HammerspoonScanner.parse(source).isEmpty)
    }

    @Test("An unknown key name is dropped, not guessed")
    func unknownKeyDropped() {
        let source = #"hs.hotkey.bind({"cmd"}, "notakey", function() end)"#
        #expect(HammerspoonScanner.parse(source).isEmpty)
    }

    @Test("A modal object's own bind method is not mistaken for hs.hotkey.bind")
    func modalBindNotMatched() {
        let source = """
        local modal = hs.hotkey.modal.new()
        modal:bind({"cmd"}, "j", function() end)
        """
        #expect(HammerspoonScanner.parse(source).isEmpty)
    }

    // MARK: - Comments

    @Test("A commented-out bind does not register")
    func lineCommentIgnored() {
        let source = """
        -- hs.hotkey.bind({"cmd"}, "Q", function() end)
        hs.hotkey.bind({"cmd"}, "W", function() end)
        """
        let bindings = HammerspoonScanner.parse(source)
        #expect(bindings.count == 1)
        #expect(bindings.first?.keyCode == 0x0D) // W, not Q
    }

    @Test("A bind inside a block comment does not register")
    func blockCommentIgnored() {
        let source = """
        --[[
        hs.hotkey.bind({"cmd"}, "Q", function() end)
        ]]
        hs.hotkey.bind({"cmd"}, "W", function() end)
        """
        let bindings = HammerspoonScanner.parse(source)
        #expect(bindings.count == 1)
        #expect(bindings.first?.keyCode == 0x0D)
    }

    @Test("A long-bracket block comment with equals levels is handled")
    func leveledBlockCommentIgnored() {
        let source = """
        --[==[
        hs.hotkey.bind({"cmd"}, "Q", function() end)
        ]==]
        hs.hotkey.bind({"cmd"}, "E", function() end)
        """
        let bindings = HammerspoonScanner.parse(source)
        #expect(bindings.count == 1)
        #expect(bindings.first?.keyCode == 0x0E) // E
    }

    // MARK: - Multiple binds and whitespace

    @Test("Every bind in a config is found")
    func multipleBinds() {
        let source = """
        hs.hotkey.bind({"cmd", "shift"}, "1", function() end)
        hs.hotkey.bind ( {"alt"} , "2" , function() end )
        hs.hotkey.bind({"ctrl"}, "3", function() end)
        """
        let bindings = HammerspoonScanner.parse(source)
        #expect(bindings.count == 3)
        #expect(bindings.map(\.keyCode).sorted() == [0x12, 0x13, 0x14].sorted())
    }

    @Test("Garbage and empty input parse to nothing")
    func garbageInput() {
        #expect(HammerspoonScanner.parse("").isEmpty)
        #expect(HammerspoonScanner.parse("print('no hotkeys here')").isEmpty)
        #expect(HammerspoonScanner.parse("hs.hotkey.bind(").isEmpty)
    }
}
