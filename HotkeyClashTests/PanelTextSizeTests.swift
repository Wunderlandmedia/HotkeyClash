import CoreGraphics
import Testing
@testable import HotkeyClash

/// Tests for the panel's text size steps and the layout that follows them.
///
/// What matters: the zoom keys walk the steps in order and stop cleanly at both
/// ends, and a big size never produces a panel larger than the screen it opens on.
@Suite("Panel text size")
struct PanelTextSizeTests {

    // MARK: - Steps

    @Test("Stepping up walks every size in order, then stops")
    func stepUp() {
        #expect(PanelTextSize.standard.stepUp == .large)
        #expect(PanelTextSize.large.stepUp == .larger)
        #expect(PanelTextSize.larger.stepUp == .largest)
        #expect(PanelTextSize.largest.stepUp == nil)
    }

    @Test("Stepping down walks back, then stops at the default")
    func stepDown() {
        #expect(PanelTextSize.largest.stepDown == .larger)
        #expect(PanelTextSize.larger.stepDown == .large)
        #expect(PanelTextSize.large.stepDown == .standard)
        #expect(PanelTextSize.standard.stepDown == nil)
    }

    @Test("Every step is strictly bigger than the one before")
    func scalesIncrease() {
        let scales = PanelTextSize.allCases.map(\.scale)
        #expect(scales.first == 1.0)
        #expect(zip(scales, scales.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("The default is stored as zero, which is what a missing key reads as")
    func defaultIsZero() {
        // SettingsManager falls back to integer(forKey:), which is 0 when the key
        // was never written. If the default ever moved off 0, every existing user
        // would silently start on some other size.
        #expect(PanelTextSize(rawValue: 0) == .standard)
    }

    // MARK: - Layout

    @Test("On a roomy screen the panel scales with the text")
    func panelScales() {
        let roomy = CGSize(width: 5000, height: 5000)
        #expect(PanelTextSize.standard.panelSize(fitting: roomy) == PanelTextSize.basePanelSize)
        #expect(PanelTextSize.largest.panelSize(fitting: roomy) == CGSize(width: 1320, height: 930))
    }

    @Test("The panel never outgrows the screen", arguments: PanelTextSize.allCases)
    func panelFitsSmallScreen(size: PanelTextSize) {
        // Roughly a 13 inch MacBook Air at its default resolution, minus menu bar and Dock.
        let small = CGSize(width: 1440, height: 810)
        let panel = size.panelSize(fitting: small)
        #expect(panel.width <= small.width)
        #expect(panel.height <= small.height)
    }

    @Test("The sidebar widens with the text")
    func sidebarWidens() {
        #expect(PanelTextSize.standard.sidebarWidth == PanelTextSize.baseSidebarWidth)
        #expect(PanelTextSize.largest.sidebarWidth == 480)
    }
}
