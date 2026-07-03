import AppKit
import Testing
@testable import HotkeyClash

/// Tests for the BetterTouchTool trigger parsing. Fixtures are synthetic store
/// rows carrying the officially documented BTT trigger JSON, so the parsing is
/// exercised without a real Core Data SQLite store.
@Suite("BetterTouchTool scanner")
struct BetterTouchToolScannerTests {

    // MARK: - Fixtures

    private func row(pk: Int64, parent: Int64? = nil, json: [String: Any]) throws -> BetterTouchToolScanner.Row {
        BetterTouchToolScanner.Row(
            pk: pk,
            parent: parent,
            json: try JSONSerialization.data(withJSONObject: json)
        )
    }

    private func shortcut(keyCode: Int, modifiers: Int, extra: [String: Any] = [:]) -> [String: Any] {
        var json: [String: Any] = [
            "BTTTriggerClass": "BTTTriggerTypeKeyboardShortcut",
            "BTTTriggerType": 0,
            "BTTShortcutKeyCode": keyCode,
            "BTTShortcutModifierKeys": modifiers,
        ]
        for (key, value) in extra { json[key] = value }
        return json
    }

    /// NSEvent.ModifierFlags raw values: shift 1<<17, control 1<<18,
    /// option 1<<19, command 1<<20.
    private let cmdShift = 1_048_576 + 131_072

    // MARK: - Parsing

    @Test("Keyboard shortcut trigger becomes a config-file binding")
    func shortcutParses() throws {
        // Cmd+Shift+K, named.
        let rows = [try row(pk: 1, json: shortcut(keyCode: 40, modifiers: cmdShift, extra: [
            "BTTTriggerTypeDescription": "Toggle window snap",
        ]))]

        let bindings = BetterTouchToolScanner.bindings(from: rows)
        let binding = try #require(bindings.first)
        #expect(bindings.count == 1)
        #expect(binding.keyCode == 40)
        #expect(binding.normalizedModifiers == [.command, .shift])
        #expect(binding.ownerName == "BetterTouchTool")
        #expect(binding.action == "Toggle window snap")
        #expect(binding.source == .configFile)
    }

    @Test("Non-keyboard triggers are ignored")
    func otherTriggerClassesIgnored() throws {
        let rows = [try row(pk: 1, json: [
            "BTTTriggerClass": "BTTTriggerTypeMagicMouse",
            "BTTShortcutKeyCode": 40,
            "BTTShortcutModifierKeys": cmdShift,
        ])]

        #expect(BetterTouchToolScanner.bindings(from: rows).isEmpty)
    }

    @Test("Disabled triggers are skipped, either enabled flag counts")
    func disabledSkipped() throws {
        let rows = [
            try row(pk: 1, json: shortcut(keyCode: 40, modifiers: cmdShift, extra: ["BTTEnabled": 0])),
            try row(pk: 2, json: shortcut(keyCode: 45, modifiers: cmdShift, extra: ["BTTEnabled2": 0])),
            try row(pk: 3, json: shortcut(keyCode: 12, modifiers: cmdShift, extra: ["BTTEnabled": 1, "BTTEnabled2": 1])),
        ]

        let bindings = BetterTouchToolScanner.bindings(from: rows)
        let binding = try #require(bindings.first)
        #expect(bindings.count == 1)
        #expect(binding.keyCode == 12)
    }

    @Test("App-scoped shortcuts are excluded, global container kept")
    func appScopingRespected() throws {
        let rows = [
            // Global container and a shortcut inside it.
            try row(pk: 1, json: ["BTTAppBundleIdentifier": "BT.G", "BTTAppName": "Global"]),
            try row(pk: 2, parent: 1, json: shortcut(keyCode: 40, modifiers: cmdShift)),
            // Finder container and a shortcut scoped to it.
            try row(pk: 3, json: ["BTTAppBundleIdentifier": "com.apple.finder", "BTTAppName": "Finder"]),
            try row(pk: 4, parent: 3, json: shortcut(keyCode: 45, modifiers: cmdShift)),
        ]

        let bindings = BetterTouchToolScanner.bindings(from: rows)
        let binding = try #require(bindings.first)
        #expect(bindings.count == 1)
        #expect(binding.keyCode == 40)
    }

    @Test("Recently Used pseudo-container (BT.L) is excluded")
    func recentlyUsedContainerExcluded() throws {
        // BT.L holds BTT's "Recently Used" copies, not live registrations.
        let rows = [
            try row(pk: 1, json: ["BTTAppBundleIdentifier": "BT.L", "BTTAppName": "Recently Used"]),
            try row(pk: 2, parent: 1, json: shortcut(keyCode: 40, modifiers: cmdShift)),
        ]

        #expect(BetterTouchToolScanner.bindings(from: rows).isEmpty)
    }

    @Test("Shortcuts with no resolvable container are kept")
    func unresolvedScopeKept() throws {
        // Parent points at a row we never fetched; assume global rather than
        // silently dropping a real registration.
        let rows = [try row(pk: 2, parent: 99, json: shortcut(keyCode: 40, modifiers: cmdShift))]
        #expect(BetterTouchToolScanner.bindings(from: rows).count == 1)
    }

    @Test("Layout-adaptive shortcuts map their character to a keycode")
    func layoutIndependentCharMaps() throws {
        let rows = [try row(pk: 1, json: shortcut(keyCode: -1, modifiers: cmdShift, extra: [
            "BTTLayoutIndependentChar": "k",
        ]))]

        let bindings = BetterTouchToolScanner.bindings(from: rows)
        let binding = try #require(bindings.first)
        #expect(bindings.count == 1)
        #expect(binding.keyCode == 40) // K
    }

    @Test("Named layout-adaptive keys map too")
    func namedCharsMap() {
        #expect(BetterTouchToolScanner.keyCode(forLayoutIndependentChar: "SPACE") == 0x31)
        #expect(BetterTouchToolScanner.keyCode(forLayoutIndependentChar: "RETURN") == 0x24)
        #expect(BetterTouchToolScanner.keyCode(forLayoutIndependentChar: "q") == 0x0C)
        #expect(BetterTouchToolScanner.keyCode(forLayoutIndependentChar: "unknown-key") == nil)
    }

    @Test("Action name falls back through notes to the predefined action")
    func actionNameFallback() throws {
        let rows = [
            try row(pk: 1, json: shortcut(keyCode: 40, modifiers: cmdShift, extra: [
                "BTTGestureNotes": "My notes name",
            ])),
            try row(pk: 2, json: shortcut(keyCode: 45, modifiers: cmdShift, extra: [
                "BTTPredefinedActionName": "Launch Application",
            ])),
            try row(pk: 3, json: shortcut(keyCode: 12, modifiers: cmdShift)),
        ]

        let actions = BetterTouchToolScanner.bindings(from: rows).map(\.action)
        #expect(actions == ["My notes name", "Launch Application", "BetterTouchTool trigger"])
    }

    @Test("Rows with non-JSON blobs are ignored without crashing")
    func garbageBlobsIgnored() {
        let rows = [BetterTouchToolScanner.Row(pk: 1, parent: nil, json: Data([0x00, 0x01, 0x02]))]
        #expect(BetterTouchToolScanner.bindings(from: rows).isEmpty)
    }
}
