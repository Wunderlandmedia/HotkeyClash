import AppKit
import Testing
@testable import HotkeyClash

/// Tests for the Services shortcut parsing. Fixtures copy the real shapes: a
/// vended entry from `com.apple.ServicesMenu.Services` and an override from
/// `pbs`'s `NSServicesStatus`, both as macOS 26 writes them.
@Suite("Services shortcut scanner", .bug(id: 12))
struct ServicesShortcutScannerTests {

    // MARK: - Helpers

    private func service(
        bundleID: String? = "com.apple.Terminal",
        path: String = "/System/Applications/Utilities/Terminal.app",
        menuItem: String = "Open man Page in Terminal",
        message: String = "openManPage",
        key: String? = "M"
    ) -> [String: Any] {
        var entry: [String: Any] = [
            "NSBundlePath": path,
            "NSMenuItem": ["default": menuItem],
            "NSMessage": message,
            "NSKeyEquivalent": key.map { ["default": $0] } ?? [String: String](),
        ]
        if let bundleID { entry["NSBundleIdentifier"] = bundleID }
        return entry
    }

    private func parse(_ vended: [[String: Any]], status: [String: Any] = [:]) -> [HotkeyBinding] {
        ServicesShortcutScanner.bindings(fromVended: vended, status: status)
    }

    // MARK: - Shipped shortcuts

    @Test("Terminal's man page service is Cmd-Shift-M, owned by Terminal")
    func terminalManPage() throws {
        let binding = try #require(parse([service()]).first)
        #expect(binding.keyCode == 0x2E)
        #expect(binding.modifiers == [.command, .shift])
        #expect(binding.ownerName == "Terminal")
        #expect(binding.ownerBundleID == "com.apple.Terminal")
        #expect(binding.action == "Open man Page in Terminal")
        #expect(binding.source == .service)
        #expect(HotkeyLayer.classify(binding) == .menuItem)
    }

    @Test("Services without a shortcut are left out")
    func noShortcut() {
        #expect(parse([service(menuItem: "New Terminal at Folder", message: "newTerminalAtFolder", key: nil)]).isEmpty)
    }

    @Test("Explicit modifier glyphs still imply Command for a shipped shortcut")
    func shippedGlyphs() throws {
        let binding = try #require(parse([service(
            bundleID: "com.apple.ChineseTextConverterService",
            path: "/System/Library/Services/ChineseTextConverterService.app",
            menuItem: "Convert Text from Traditional to Simplified Chinese",
            message: "convertTextToSimplifiedChinese",
            key: "$^~@C"
        )]).first)
        #expect(binding.keyCode == 0x08)
        #expect(binding.modifiers == [.command, .shift, .control, .option])
    }

    // MARK: - User overrides

    @Test("A service switched off in Settings is skipped")
    func disabledByUser() {
        let status: [String: Any] = [
            "com.apple.Terminal - Open man Page in Terminal - openManPage": [
                "presentation_modes": ["ContextMenu": false, "ServicesMenu": false],
            ],
        ]
        #expect(parse([service()], status: status).isEmpty)
    }

    @Test("The older enabled_services_menu flag is honoured too")
    func legacyDisableFlag() {
        let status: [String: Any] = [
            "com.apple.Terminal - Open man Page in Terminal - openManPage": ["enabled_services_menu": false],
        ]
        #expect(parse([service()], status: status).isEmpty)
    }

    @Test("A user's own shortcut replaces the shipped one, with no implied Command")
    func customShortcut() throws {
        let status: [String: Any] = [
            "com.apple.Terminal - Open man Page in Terminal - openManPage": ["key_equivalent": "^~k"],
        ]
        let binding = try #require(parse([service()], status: status).first)
        #expect(binding.keyCode == 0x28)
        #expect(binding.modifiers == [.control, .option])
    }

    @Test("A cleared shortcut means no binding")
    func clearedShortcut() {
        let status: [String: Any] = [
            "com.apple.Terminal - Open man Page in Terminal - openManPage": ["key_equivalent": ""],
        ]
        #expect(parse([service()], status: status).isEmpty)
    }

    @Test("A workflow with a shortcut is matched under the (null) key and named after its file")
    func workflow() throws {
        let path = "/Users/me/Library/Services/Send to Claude.workflow"
        let vended = [service(bundleID: nil, path: path, menuItem: "Send to Claude", message: "runWorkflowAsService", key: nil)]
        let status: [String: Any] = ["(null) - Send to Claude - runWorkflowAsService": ["key_equivalent": "@~s"]]
        let binding = try #require(parse(vended, status: status).first)
        #expect(binding.ownerName == "Send to Claude")
        #expect(binding.ownerBundleID == nil)
        #expect(binding.modifiers == [.command, .option])
    }

    // MARK: - Defaults

    @Test("Services that start switched off stay off until the user enables them")
    func defaultOff() throws {
        let bluetooth = service(
            bundleID: "com.apple.BluetoothFileExchange",
            path: "/System/Applications/Utilities/Bluetooth File Exchange.app",
            menuItem: "Send File To Bluetooth Device",
            message: "sendFileUsingBluetoothOBEXService",
            key: "B"
        )
        #expect(parse([bluetooth]).isEmpty)

        let enabled: [String: Any] = [
            "com.apple.BluetoothFileExchange - Send File To Bluetooth Device - sendFileUsingBluetoothOBEXService": [
                "presentation_modes": ["ServicesMenu": true],
            ],
        ]
        #expect(parse([bluetooth], status: enabled).count == 1)
    }

    // MARK: - Key equivalents and titles

    @Test("Key equivalents parse the way NSMenu reads them")
    func keyEquivalents() throws {
        let shiftedY = try #require(ServicesShortcutScanner.parseKeyEquivalent("Y", impliesCommand: true))
        #expect(shiftedY.keyCode == 0x10)
        #expect(shiftedY.modifiers == [.command, .shift])

        let plain = try #require(ServicesShortcutScanner.parseKeyEquivalent("@l", impliesCommand: false))
        #expect(plain.modifiers == [.command])

        #expect(ServicesShortcutScanner.parseKeyEquivalent("", impliesCommand: true) == nil)
        #expect(ServicesShortcutScanner.parseKeyEquivalent("*", impliesCommand: true) == nil)
        #expect(ServicesShortcutScanner.parseKeyEquivalent("@xy", impliesCommand: false) == nil)
    }

    @Test("Titles drop the submenu path and spell out Safari's placeholder")
    func titles() {
        #expect(ServicesShortcutScanner.displayTitle(menuItem: ["default": "Script Editor/Get Result of AppleScript"]) == "Get Result of AppleScript")
        #expect(ServicesShortcutScanner.displayTitle(menuItem: ["default": "Search With %WebSearchProvider@"]) == "Search With Web Search Provider")
    }
}
