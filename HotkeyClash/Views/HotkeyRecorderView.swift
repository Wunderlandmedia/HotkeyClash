import Carbon
import SwiftUI

struct HotkeyRecorderView: View {
    private var settings: SettingsManager { .shared }
    @State private var isRecording = false
    @State private var showReservedWarning = false

    var body: some View {
        HStack(spacing: 8) {
            if isRecording {
                Text("Press shortcut...")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.orange)
                    .frame(minWidth: 120, alignment: .trailing)
                Button("Cancel") {
                    isRecording = false
                }
                .controlSize(.small)
            } else {
                Text(currentShortcutDisplay)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button("Change") {
                    isRecording = true
                }
                .controlSize(.small)
            }
        }
        .background {
            if isRecording {
                KeyCaptureView { keyCode, modifiers in
                    handleRecordedShortcut(keyCode: keyCode, modifiers: modifiers)
                }
                .frame(width: 0, height: 0)
            }
        }
        .popover(isPresented: $showReservedWarning, arrowEdge: .bottom) {
            Text("That shortcut is reserved by macOS. Try a different combination.")
                .font(.caption)
                .padding(12)
        }
    }

    private var currentShortcutDisplay: String {
        ShortcutFormatter.displayString(
            keyCode: settings.globalShortcutKeyCode,
            carbonModifiers: settings.globalShortcutModifiers
        )
    }

    private func handleRecordedShortcut(keyCode: UInt32, modifiers: UInt32) {
        if ShortcutFormatter.isReserved(keyCode: keyCode, carbonModifiers: modifiers) {
            showReservedWarning = true
            return
        }

        settings.globalShortcutKeyCode = keyCode
        settings.globalShortcutModifiers = modifiers
        HotKeyManager.shared.reregister(keyCode: keyCode, modifiers: modifiers)
        isRecording = false
    }
}

private struct KeyCaptureView: NSViewRepresentable {
    let onCapture: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onCapture = onCapture
        Task { @MainActor in
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onCapture = onCapture
    }
}

private final class KeyCaptureNSView: NSView {
    var onCapture: ((UInt32, UInt32) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !modifiers.intersection([.command, .control, .option]).isEmpty else { return }

        let carbonMods = ShortcutFormatter.carbonModifiers(from: modifiers)
        onCapture?(UInt32(event.keyCode), carbonMods)
    }
}
