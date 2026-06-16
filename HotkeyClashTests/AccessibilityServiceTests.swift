import AppKit
import Testing
@testable import HotkeyClash

/// Tests for the pure AX translation helpers: character/glyph to virtual key code,
/// and AX modifier flags to NSEvent.ModifierFlags. These changed when menu-bar app
/// scanning was widened, so they are pinned here.
@Suite("AccessibilityService mapping")
struct AccessibilityServiceTests {

    // MARK: - keyCode(for:)

    @Test("Letters map to their virtual key codes, case-insensitively")
    func lettersMap() {
        #expect(AccessibilityService.keyCode(for: "c") == 0x08)
        #expect(AccessibilityService.keyCode(for: "C") == 0x08)
        #expect(AccessibilityService.keyCode(for: "q") == 0x0C)
    }

    @Test("Control characters for return, tab, and escape map")
    func specialCharsMap() {
        #expect(AccessibilityService.keyCode(for: "\r") == 0x24) // Return
        #expect(AccessibilityService.keyCode(for: "\t") == 0x30) // Tab
        #expect(AccessibilityService.keyCode(for: "\u{1B}") == 0x35) // Escape
        #expect(AccessibilityService.keyCode(for: " ") == 0x31) // Space
    }

    @Test("Unmapped characters return nil")
    func unmappedReturnsNil() {
        #expect(AccessibilityService.keyCode(for: "\u{2318}") == nil) // Command glyph
        #expect(AccessibilityService.keyCode(for: "") == nil)
    }

    // MARK: - convertAXModifiers

    @Test("Command is implied when the no-command flag is absent")
    func commandImplied() {
        #expect(AccessibilityService.convertAXModifiers(0x00) == [.command])
    }

    @Test("The 0x08 flag explicitly excludes Command")
    func noCommandFlag() {
        #expect(AccessibilityService.convertAXModifiers(0x08) == [])
    }

    @Test("Shift, Option, and Control flags combine with the implied Command")
    func modifierCombinations() {
        #expect(AccessibilityService.convertAXModifiers(0x01) == [.command, .shift])
        #expect(AccessibilityService.convertAXModifiers(0x02) == [.command, .option])
        #expect(AccessibilityService.convertAXModifiers(0x04) == [.command, .control])
        #expect(AccessibilityService.convertAXModifiers(0x01 | 0x02 | 0x04) == [.command, .shift, .option, .control])
    }
}
