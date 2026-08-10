import AppKit
import SwiftUI

@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private var eventMonitor: Any?
    private var localEventMonitor: Any?
    private(set) var previousApp: NSRunningApplication?

    func setup(with contentView: some View) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            let image = NSImage(named: "MenuBarIcon")
            image?.isTemplate = true
            button.image = image
            button.action = #selector(togglePanel)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        panel = FloatingPanel(contentView: contentView)
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent

        if event?.type == .rightMouseUp {
            showContextMenu(from: sender)
            return
        }

        if panel.isVisible {
            hidePopover()
        } else {
            showPopover()
        }
    }

    /// Whether the panel is on screen. The auto rescan asks before scanning, so it
    /// never rebuilds the list while someone is reading it.
    var isPanelVisible: Bool { panel?.isVisible ?? false }

    func showPopover() {
        previousApp = NSWorkspace.shared.frontmostApplication
        panel.cancelDismiss()
        panel.restorePosition()
        panel.makeKeyAndOrderFront(nil)
        panel.animateIn()
        NSApp.activate()
        startEventMonitor()
    }

    func hidePopover() {
        panel.animateOut { [weak self] in
            self?.panel.orderOut(nil)
        }
        stopEventMonitor()
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Rescan", action: #selector(triggerRescan), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit HotkeyClash", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }
        menu.items.last?.target = NSApp

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func triggerRescan() {
        NotificationCenter.default.post(name: .triggerRescan, object: nil)
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }

    func updateBadge(count: Int) {
        guard let button = statusItem.button else { return }

        let icon = NSImage(named: "MenuBarIcon")
        icon?.isTemplate = true

        if count > 0 {
            let badgeSize = NSSize(width: 22, height: 22)
            let compositeImage = NSImage(size: badgeSize, flipped: false) { rect in
                // Draw the original icon
                if let icon {
                    icon.draw(in: rect)
                }

                // Draw badge circle
                let badgeDiameter: CGFloat = 10
                let badgeRect = NSRect(
                    x: rect.maxX - badgeDiameter,
                    y: rect.maxY - badgeDiameter,
                    width: badgeDiameter,
                    height: badgeDiameter
                )
                NSColor.systemRed.setFill()
                NSBezierPath(ovalIn: badgeRect).fill()

                // Draw count text
                let text = count > 9 ? "+" : "\(count)"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 7, weight: .bold),
                    .foregroundColor: NSColor.white
                ]
                let textSize = (text as NSString).size(withAttributes: attrs)
                let textPoint = NSPoint(
                    x: badgeRect.midX - textSize.width / 2,
                    y: badgeRect.midY - textSize.height / 2
                )
                (text as NSString).draw(at: textPoint, withAttributes: attrs)

                return true
            }
            compositeImage.isTemplate = false
            button.image = compositeImage
        } else {
            button.image = icon
        }
    }

    private func startEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePopover()
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.hidePopover()
                return nil
            }
            return event
        }
    }

    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }
}

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
    static let triggerRescan = Notification.Name("triggerRescan")
    static let dismissPanel = Notification.Name("dismissPanel")
}

final class FloatingPanel: NSPanel {
    private var dismissTask: Task<Void, Never>?

    init(contentView: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )

        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Draggable by its background: with no title bar there is nowhere else to
        // grab it, and a panel you cannot move is a panel permanently in the way.
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostView = NSHostingView(rootView:
            contentView
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.background)
                        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
                        .shadow(color: .black.opacity(0.06), radius: 1, y: 0)
                )
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
        )
        self.contentView = hostView
        delegate = self
    }

    /// Puts the panel back where the user left it, or centres it if that spot is
    /// no longer sensible.
    ///
    /// "No longer sensible" is mostly about displays. Move the panel onto a second
    /// monitor, unplug it, and the saved origin now points into empty space where
    /// the panel would be invisible with no way to drag it back. So we insist the
    /// restored frame still overlaps a connected screen by a decent margin before
    /// trusting it.
    func restorePosition() {
        guard let origin = SettingsManager.shared.panelOrigin,
              Self.isUsable(origin: origin, size: frame.size) else {
            centerOnScreen()
            return
        }
        setFrameOrigin(origin)
    }

    /// Records where the panel is now, so the next open lands in the same place.
    func savePosition() {
        SettingsManager.shared.panelOrigin = frame.origin
    }

    func centerOnScreen() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.midY - frame.height / 2
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// A saved spot counts as usable when a fair chunk of the panel would still be
    /// on some screen. A sliver poking onto a display is technically visible and
    /// practically useless, hence the area test rather than a plain intersection.
    private static func isUsable(origin: CGPoint, size: CGSize) -> Bool {
        let proposed = NSRect(origin: origin, size: size)
        let minimumVisible = proposed.width * proposed.height * 0.5
        return NSScreen.screens.contains { screen in
            let overlap = screen.visibleFrame.intersection(proposed)
            guard !overlap.isNull else { return false }
            return overlap.width * overlap.height >= minimumVisible
        }
    }

    func animateIn() {
        guard let layer = contentView?.layer else { return }
        contentView?.wantsLayer = true

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            layer.setAffineTransform(.identity)
            alphaValue = 1
            return
        }

        alphaValue = 0
        layer.setAffineTransform(CGAffineTransform(scaleX: 1.05, y: 1.05))

        let scaleAnim = CASpringAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 1.05
        scaleAnim.toValue = 1.0
        scaleAnim.mass = 0.8
        scaleAnim.stiffness = 300
        scaleAnim.damping = 18
        scaleAnim.duration = scaleAnim.settlingDuration

        let opacityAnim = CABasicAnimation(keyPath: "opacity")
        opacityAnim.fromValue = 0.0
        opacityAnim.toValue = 1.0
        opacityAnim.duration = 0.15

        layer.add(scaleAnim, forKey: "scaleIn")
        layer.add(opacityAnim, forKey: "fadeIn")

        layer.setAffineTransform(.identity)
        alphaValue = 1
    }

    func animateOut(completion: @escaping () -> Void) {
        guard let layer = contentView?.layer else {
            completion()
            return
        }

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            alphaValue = 0
            completion()
            return
        }

        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 1.0
        scaleAnim.toValue = 0.97
        scaleAnim.duration = 0.12

        let opacityAnim = CABasicAnimation(keyPath: "opacity")
        opacityAnim.fromValue = 1.0
        opacityAnim.toValue = 0.0
        opacityAnim.duration = 0.12

        layer.setAffineTransform(CGAffineTransform(scaleX: 0.97, y: 0.97))
        alphaValue = 0

        layer.add(scaleAnim, forKey: "scaleOut")
        layer.add(opacityAnim, forKey: "fadeOut")

        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            completion()
        }
    }

    func cancelDismiss() {
        dismissTask?.cancel()
        dismissTask = nil
    }

    override var canBecomeKey: Bool { true }
}

extension FloatingPanel: NSWindowDelegate {
    /// Save on every move rather than only on close, so a crash or a force quit
    /// cannot lose the position the user just chose.
    func windowDidMove(_ notification: Notification) {
        savePosition()
    }
}
