import AppKit
import Testing
@testable import HotkeyClash

/// Tests for the event-stack classification that the likely-winner hint rests on.
/// Every tool HotkeyClash parses should land on a deliberate layer, not the
/// catch-all, so a new scanner that forgets to register itself fails here.
@Suite("Hotkey layer")
struct HotkeyLayerTests {

    private func binding(
        owner: String,
        bundleID: String?,
        source: HotkeyBinding.BindingSource
    ) -> HotkeyBinding {
        HotkeyBinding(
            keyCode: 0x0C,
            modifiers: [.command],
            ownerName: owner,
            ownerBundleID: bundleID,
            action: "Action",
            source: source
        )
    }

    // MARK: - Ordering

    @Test("Layers order from earliest hook to latest")
    func ordering() {
        #expect(HotkeyLayer.driver < HotkeyLayer.eventTap)
        #expect(HotkeyLayer.eventTap < HotkeyLayer.system)
        #expect(HotkeyLayer.system < HotkeyLayer.globalHotKey)
        #expect(HotkeyLayer.globalHotKey < HotkeyLayer.otherGlobal)
        #expect(HotkeyLayer.otherGlobal < HotkeyLayer.menuItem)
    }

    @Test("Menu items are the last layer to see a key")
    func menuItemIsLast() {
        #expect(HotkeyLayer.allCases.max() == .menuItem)
    }

    // MARK: - Classification

    @Test("Source alone decides system and menu bar bindings")
    func sourceDrivenLayers() {
        let system = binding(owner: "macOS", bundleID: "com.apple.systempreferences", source: .systemShortcut)
        let menu = binding(owner: "Safari", bundleID: "com.apple.Safari", source: .menuBar)

        #expect(HotkeyLayer.classify(system) == .system)
        #expect(HotkeyLayer.classify(menu) == .menuItem)
    }

    /// One row of the tool-to-layer table, named so failures read clearly.
    struct ToolCase: CustomTestStringConvertible {
        let owner: String
        let bundleID: String?
        let expected: HotkeyLayer

        var testDescription: String { "\(owner) is \(expected.label)" }
    }

    @Test(
        "Each parsed config tool maps to its own layer",
        arguments: [
            ToolCase(owner: "Karabiner-Elements", bundleID: "org.pqrs.Karabiner-Elements", expected: .driver),
            ToolCase(owner: "skhd", bundleID: nil, expected: .eventTap),
            ToolCase(owner: "BetterTouchTool", bundleID: "com.hegenberg.BetterTouchTool", expected: .eventTap),
            ToolCase(owner: "Keyboard Maestro", bundleID: "com.stairways.keyboardmaestro.engine", expected: .eventTap),
            ToolCase(owner: "Hammerspoon", bundleID: "org.hammerspoon.Hammerspoon", expected: .globalHotKey),
            ToolCase(owner: "Alfred", bundleID: "com.runningwithcrayons.Alfred", expected: .globalHotKey),
        ]
    )
    func configToolLayers(tool: ToolCase) {
        let b = binding(owner: tool.owner, bundleID: tool.bundleID, source: .configFile)
        #expect(HotkeyLayer.classify(b) == tool.expected)
    }

    @Test("An unrecognised global tool still outranks app menus")
    func unknownGlobalTool() {
        let b = binding(owner: "SomeNewTool", bundleID: "com.example.new", source: .configFile)
        #expect(HotkeyLayer.classify(b) == .otherGlobal)
        #expect(HotkeyLayer.classify(b) < .menuItem)
    }

    // MARK: - Copy

    @Test("Layer copy follows the no em dash convention")
    func noEmDashes() {
        for layer in HotkeyLayer.allCases {
            #expect(layer.label.contains("\u{2014}") == false, "\(layer.label) label has an em dash")
            #expect(layer.explanation.contains("\u{2014}") == false, "\(layer.label) explanation has an em dash")
        }
    }
}
