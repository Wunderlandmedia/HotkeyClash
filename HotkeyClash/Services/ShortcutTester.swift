import AppKit
import Observation
import os

private let logger = Logger(subsystem: "com.hotkeyclash.app", category: "ShortcutTester")

/// Watches one real keypress and reports what happened to it.
///
/// The scan can only read what tools wrote down, so the winner it names is an
/// educated guess. This is the other half of the answer: press the key and see.
///
/// The trick is listening twice. macOS keeps event taps in an ordered chain, and
/// a tap that claims a key stops it dead. So we insert one listener at the head
/// of that chain, ahead of everyone, and append another at the tail, behind
/// everyone. If the head hears the key and the tail never does, some other app's
/// tap ate it in between. That is a fact rather than an inference, and it is the
/// one thing the config files can never tell us.
///
/// Above the tap layer we go blind. A system shortcut or a Carbon global hotkey
/// consumes a key with no observable side effect, so all we have left is whether
/// an app came to the front. `ShortcutTestVerdict` is careful about the
/// difference between those two kinds of knowledge.
@MainActor
@Observable
final class ShortcutTester {

    enum State {
        case idle
        /// Cannot test right now, with the reason in user-facing words.
        case unavailable(String)
        case listening(secondsRemaining: Int)
        /// The observation, or nil when the window closed without a keypress.
        case finished(ShortcutTestResult?)
    }

    /// How long to listen before giving up. Long enough to switch apps and press
    /// something deliberately, short enough that a forgotten test expires on its own.
    private static let listenWindow = 15

    /// How long to wait after the key arrives at the head tap before deciding what
    /// happened. It covers two things at once: the tail tap fires within a
    /// millisecond or two if the key survived, and an app that reacts to a hotkey
    /// takes a beat to actually come to the front.
    private static let settleDelay = Duration.milliseconds(600)

    private(set) var state: State = .idle

    /// Which conflict the current state belongs to, so a stale result from another
    /// row never shows up under the one now selected.
    private(set) var conflictID: UUID?

    /// The app to hand focus back to while the test runs. HotkeyClash being
    /// frontmost would poison the result: menu shortcuts fire for whoever is in
    /// front, and that must not be us.
    private let appToRestore: () -> NSRunningApplication?

    /// Told when listening starts and stops, so the panel can stop dismissing
    /// itself on the click that moves the user into another app.
    private let onListeningChanged: (Bool) -> Void

    private var headTap: CFMachPort?
    private var tailTap: CFMachPort?
    private var runLoopSources: [CFRunLoopSource] = []
    private var activationObserver: NSObjectProtocol?
    private var countdownTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?

    private var expectedKeyCode: UInt16 = 0
    private var expectedModifiers: NSEvent.ModifierFlags = []

    /// The press being resolved: recorded when the head tap sees it, completed
    /// once the settle delay is up.
    private var pendingPress: PendingPress?

    private struct PendingPress {
        let keyCode: UInt16
        let modifiers: NSEvent.ModifierFlags
        let frontmostApp: ShortcutTestResult.App?
        var reachedTail = false
        var activatedApp: ShortcutTestResult.App?
    }

    /// A tail sighting that arrived before its head sighting did.
    ///
    /// The two taps are separate run loop sources, and a run loop makes no promise
    /// about the order it drains sources signalled in the same pass. In testing the
    /// head always came first, but "always so far" is not an ordering guarantee,
    /// and getting this backwards would report the key as swallowed by an event tap
    /// when nothing touched it. That is the one claim this feature must not get
    /// wrong, so the tail is allowed to arrive first and wait to be claimed.
    private var earlyTail: (keyCode: UInt16, modifiers: NSEvent.ModifierFlags, at: ContinuousClock.Instant)?

    /// How stale an unclaimed tail sighting can be and still belong to the press
    /// now arriving at the head. The two are microseconds apart in practice; this
    /// is wide enough to never matter and narrow enough that an unrelated press of
    /// the same combo seconds earlier can never be mistaken for it.
    private static let tailPairingWindow = Duration.milliseconds(50)

    init(
        appToRestore: @escaping () -> NSRunningApplication?,
        onListeningChanged: @escaping (Bool) -> Void
    ) {
        self.appToRestore = appToRestore
        self.onListeningChanged = onListeningChanged
    }

    // MARK: - Running a test

    func start(for conflict: Conflict) {
        teardown()
        conflictID = conflict.id

        // The taps are the same privilege the scan already asked for, so in
        // practice this only bites someone who revoked it since launch.
        guard AccessibilityService.checkPermission() else {
            state = .unavailable("Testing a shortcut needs Accessibility permission. Grant it in System Settings, then try again.")
            return
        }

        guard installTaps() else {
            state = .unavailable("macOS refused to install the keyboard listener. Quitting and reopening HotkeyClash usually clears this.")
            return
        }

        expectedKeyCode = conflict.keyCode
        expectedModifiers = conflict.modifiers.intersection([.command, .option, .shift, .control])
        pendingPress = nil
        state = .listening(secondsRemaining: Self.listenWindow)
        onListeningChanged(true)
        watchForActivation()
        stepAside()
        startCountdown()
        logger.info("Listening for a test press")
    }

    func cancel() {
        teardown()
        state = .idle
        conflictID = nil
    }

    /// Called when the user navigates to another conflict. A test still listening
    /// is abandoned, since the combo on screen no longer matches what it is waiting
    /// for. A finished one is left alone, so coming back to that row still shows
    /// what the test found.
    func cancelIfListening() {
        if case .listening = state { cancel() }
    }

    /// The verdict for a finished test of `conflict`, or nil when no test of this
    /// conflict has produced one. Built here so the callout and the binding list
    /// read the same verdict rather than each deriving their own.
    func verdict(for conflict: Conflict) -> ShortcutTestVerdict? {
        guard conflictID == conflict.id, case .finished(let result) = state else { return nil }
        return ShortcutTestVerdict.evaluate(
            result: result,
            bindings: conflict.bindings,
            expectedKeyCode: conflict.keyCode,
            expectedModifiers: conflict.modifiers
        )
    }

    /// Hands focus back to whatever the user was in before opening the panel, so
    /// the press happens in a realistic context rather than against our own panel.
    /// They are free to click somewhere else instead; the panel stays put while a
    /// test is running.
    private func stepAside() {
        appToRestore()?.activate()
    }

    private func startCountdown() {
        countdownTask = Task { [weak self] in
            for remaining in stride(from: Self.listenWindow - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                guard case .listening = state else { return }
                if remaining == 0 {
                    finish(with: nil)
                } else {
                    state = .listening(secondsRemaining: remaining)
                }
            }
        }
    }

    private func finish(with result: ShortcutTestResult?) {
        teardown()
        state = .finished(result)
        logger.info("Test finished: \(result == nil ? "no keypress seen" : "observed a press")")
    }

    private func teardown() {
        countdownTask?.cancel()
        countdownTask = nil
        settleTask?.cancel()
        settleTask = nil
        pendingPress = nil
        earlyTail = nil

        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }

        removeTaps()

        // Only ever a resume: this runs at the end of a test, never at the start.
        onListeningChanged(false)
    }

    // MARK: - Observing

    /// Records the press the moment the head tap sees it, then waits out the settle
    /// delay to learn whether it survived the tap chain and whether anything reacted.
    fileprivate func observeAtHead(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        guard case .listening = state, pendingPress == nil else { return }
        // A bare letter is a keystroke, not a shortcut. Same filter the recorder
        // uses, so a stray keypress while switching apps does not end the test.
        guard !modifiers.intersection([.command, .control, .option]).isEmpty else { return }

        var press = PendingPress(
            keyCode: keyCode,
            modifiers: modifiers,
            frontmostApp: Self.describe(NSWorkspace.shared.frontmostApplication)
        )
        // The tail may have got here first. If it did, this press already has its
        // answer and the settle delay is only waiting on the app activation.
        if let earlyTail, earlyTail.keyCode == keyCode, earlyTail.modifiers == modifiers,
           earlyTail.at.duration(to: .now) < Self.tailPairingWindow {
            press.reachedTail = true
        }
        earlyTail = nil
        pendingPress = press

        countdownTask?.cancel()
        countdownTask = nil

        settleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, let self, let press = pendingPress else { return }
            finish(with: ShortcutTestResult(
                keyCode: press.keyCode,
                modifiers: press.modifiers,
                tapOutcome: press.reachedTail ? .survivedTapLayer : .swallowedByEventTap,
                activatedApp: press.activatedApp,
                frontmostApp: press.frontmostApp
            ))
        }
    }

    /// The same press arriving at the far end of the tap chain, which means nothing
    /// in between claimed it. Matched on the combo rather than on event identity:
    /// the two taps see the same event, and only one press is ever in flight here.
    fileprivate func observeAtTail(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        guard case .listening = state else { return }

        guard var press = pendingPress else {
            // No head sighting yet. Either this is a key we are not interested in,
            // or the run loop handed us the two sources out of order; hold it for a
            // moment in case the head is right behind.
            earlyTail = (keyCode, modifiers, .now)
            return
        }

        guard press.keyCode == keyCode, press.modifiers == modifiers else { return }
        press.reachedTail = true
        pendingPress = press
    }

    fileprivate func reenableTaps() {
        for tap in [headTap, tailTap].compactMap({ $0 }) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        logger.debug("Re-enabled a tap macOS had disabled")
    }

    private func watchForActivation() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Delivered on the main queue, which is a queue guarantee rather than
            // an actor one, so hop explicitly.
            MainActor.assumeIsolated {
                self?.appActivated(notification)
            }
        }
    }

    private func appActivated(_ notification: Notification) {
        // Only activations that follow the press count. Handing focus back at the
        // start of the test raises one of these too, and it means nothing.
        guard var press = pendingPress, press.activatedApp == nil else { return }
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        // The app the user was already in coming back to the front is just focus
        // settling, not an app reacting to the shortcut.
        guard app.bundleIdentifier != press.frontmostApp?.bundleID else { return }

        press.activatedApp = Self.describe(app)
        pendingPress = press
    }

    private static func describe(_ app: NSRunningApplication?) -> ShortcutTestResult.App? {
        guard let app else { return nil }
        return ShortcutTestResult.App(
            name: app.localizedName ?? app.bundleIdentifier ?? "an app",
            bundleID: app.bundleIdentifier
        )
    }

    // MARK: - Taps

    /// Installs the two listeners that make this feature work: one ahead of every
    /// other event tap, one behind them all.
    ///
    /// Both are listen-only. HotkeyClash must never be able to change or swallow a
    /// key, and a passive tap also cannot break a shortcut it is watching.
    private func installTaps() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        // Unretained is safe because the tester outlives every tap it creates:
        // teardown always runs before this object goes away.
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let head = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: headTapCallback,
            userInfo: context
        ), let tail = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: tailTapCallback,
            userInfo: context
        ) else {
            // One of the two may have been created. Clear up rather than leave a
            // half-installed pair listening with nothing to report to.
            removeTaps()
            return false
        }

        headTap = head
        tailTap = tail

        for tap in [head, tail] {
            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { continue }
            // The main run loop on purpose: it puts the callbacks on the main
            // thread, which is what lets them talk to this main-actor type directly.
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSources.append(source)
            CGEvent.tapEnable(tap: tap, enable: true)
        }

        return true
    }

    private func removeTaps() {
        for source in runLoopSources {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSources.removeAll()

        for tap in [headTap, tailTap].compactMap({ $0 }) {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        headTap = nil
        tailTap = nil
    }
}

// MARK: - Tap callbacks

/// Both callbacks are plain C function pointers, so they take the tester back out
/// of the opaque context pointer they were handed. They run on the main thread
/// because the run loop sources are on the main run loop, which is what makes
/// `assumeIsolated` honest here rather than a gamble.
private nonisolated func headTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    handleTapEvent(type: type, event: event, userInfo: userInfo, atHead: true)
}

private nonisolated func tailTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    handleTapEvent(type: type, event: event, userInfo: userInfo, atHead: false)
}

private nonisolated func handleTapEvent(
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?,
    atHead: Bool
) -> Unmanaged<CGEvent>? {
    // Always hand the event straight back. This tap observes and nothing more.
    let passthrough = Unmanaged.passUnretained(event)
    guard let userInfo else { return passthrough }

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated {
            Unmanaged<ShortcutTester>.fromOpaque(userInfo).takeUnretainedValue().reenableTaps()
        }
        return passthrough
    }

    guard type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return passthrough }

    let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    // CGEventFlags and NSEvent.ModifierFlags use the same bit positions for the
    // four modifiers we care about, so the raw value carries across untouched.
    let modifiers = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        .intersection([.command, .option, .shift, .control])

    MainActor.assumeIsolated {
        let tester = Unmanaged<ShortcutTester>.fromOpaque(userInfo).takeUnretainedValue()
        if atHead {
            tester.observeAtHead(keyCode: keyCode, modifiers: modifiers)
        } else {
            tester.observeAtTail(keyCode: keyCode, modifiers: modifiers)
        }
    }

    return passthrough
}
