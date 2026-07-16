import AppKit
import Foundation
import os

private let logger = Logger(subsystem: "com.hotkeyclash.app", category: "ConfigFileScanner")

@MainActor
final class ConfigFileScanner {

    /// Upper bound on a config file we are willing to read into memory.
    private static let maxConfigBytes = 10 * 1024 * 1024

    /// The heavier tools keep their parsers in their own files; this scanner
    /// stays the one place that knows the full list of config sources.
    private let keyboardMaestro = KeyboardMaestroScanner()
    private let betterTouchTool = BetterTouchToolScanner()
    private let hammerspoon = HammerspoonScanner()

    // MARK: - Public

    func scan() async -> [HotkeyBinding] {
        var bindings: [HotkeyBinding] = []
        bindings.append(contentsOf: scanKarabiner())
        bindings.append(contentsOf: scanSkhd())
        bindings.append(contentsOf: await keyboardMaestro.scan())
        bindings.append(contentsOf: await betterTouchTool.scan())
        bindings.append(contentsOf: await hammerspoon.scan())
        return bindings
    }

    // MARK: - Karabiner-Elements

    private func scanKarabiner() -> [HotkeyBinding] {
        let path = NSString("~/.config/karabiner/karabiner.json").expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else {
            logger.debug("Karabiner config not found at \(path)")
            return []
        }

        // Guard against unbounded reads (corrupted file, symlink to a device, an
        // adversarially large shared config, etc.) before loading into memory.
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int, size > Self.maxConfigBytes {
            logger.warning("Karabiner config exceeds size limit (\(size) bytes), skipping")
            return []
        }

        guard let data = FileManager.default.contents(atPath: path) else {
            logger.warning("Could not read Karabiner config")
            return []
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profiles = json["profiles"] as? [[String: Any]] else {
            logger.warning("Could not parse Karabiner config JSON")
            return []
        }

        // Find active profile, or use the first one
        let profile = profiles.first(where: { $0["selected"] as? Bool == true }) ?? profiles.first
        guard let profile else { return [] }

        guard let complexMods = profile["complex_modifications"] as? [String: Any],
              let rules = complexMods["rules"] as? [[String: Any]] else {
            return []
        }

        var bindings: [HotkeyBinding] = []

        for rule in rules {
            let ruleDescription = rule["description"] as? String ?? "Karabiner rule"
            guard let manipulators = rule["manipulators"] as? [[String: Any]] else { continue }

            for manipulator in manipulators {
                guard let from = manipulator["from"] as? [String: Any] else { continue }

                guard let keyCodeName = from["key_code"] as? String,
                      let keyCode = karabinerKeyMap[keyCodeName] else { continue }

                var modifiers: NSEvent.ModifierFlags = []

                if let modsDict = from["modifiers"] as? [String: Any] {
                    if let mandatory = modsDict["mandatory"] as? [String] {
                        for mod in mandatory {
                            modifiers.formUnion(karabinerModifier(mod))
                        }
                    }
                }

                let binding = HotkeyBinding(
                    keyCode: keyCode,
                    modifiers: modifiers,
                    ownerName: "Karabiner-Elements",
                    ownerBundleID: "org.pqrs.Karabiner-Elements",
                    action: ruleDescription,
                    source: .configFile
                )
                bindings.append(binding)
            }
        }

        logger.info("Karabiner: found \(bindings.count) bindings")
        return bindings
    }

    private func karabinerModifier(_ name: String) -> NSEvent.ModifierFlags {
        switch name {
        case "command", "left_command", "right_command": return .command
        case "shift", "left_shift", "right_shift": return .shift
        case "option", "left_option", "right_option": return .option
        case "control", "left_control", "right_control": return .control
        default: return []
        }
    }

    // MARK: - skhd

    private func scanSkhd() -> [HotkeyBinding] {
        let path = NSString("~/.config/skhd/skhdrc").expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else {
            logger.debug("skhd config not found at \(path)")
            return []
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int, size > Self.maxConfigBytes {
            logger.warning("skhd config exceeds size limit (\(size) bytes), skipping")
            return []
        }

        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            logger.warning("Could not read skhd config")
            return []
        }

        var bindings: [HotkeyBinding] = []

        for line in contents.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // Format: modifier - key : command
            // or:     modifier + modifier - key : command
            guard let colonIndex = trimmed.firstIndex(of: ":") else { continue }

            let hotkeyPart = String(trimmed[trimmed.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let commandPart = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

            // Split hotkey into modifiers and key by the last " - "
            guard let dashRange = hotkeyPart.range(of: " - ", options: .backwards) else { continue }
            let modifiersPart = String(hotkeyPart[hotkeyPart.startIndex..<dashRange.lowerBound])
            let keyPart = String(hotkeyPart[dashRange.upperBound...]).trimmingCharacters(in: .whitespaces)

            guard let keyCode = skhdKeyMap[keyPart.lowercased()] else {
                logger.debug("Unknown skhd key: \(keyPart)")
                continue
            }

            var modifiers: NSEvent.ModifierFlags = []
            let modTokens = modifiersPart.components(separatedBy: "+").map {
                $0.trimmingCharacters(in: .whitespaces).lowercased()
            }
            for mod in modTokens {
                switch mod {
                case "cmd": modifiers.insert(.command)
                case "shift": modifiers.insert(.shift)
                case "alt", "opt": modifiers.insert(.option)
                case "ctrl": modifiers.insert(.control)
                case "hyper":
                    modifiers.formUnion([.command, .option, .shift, .control])
                case "meh":
                    modifiers.formUnion([.option, .shift, .control])
                default: break
                }
            }

            let binding = HotkeyBinding(
                keyCode: keyCode,
                modifiers: modifiers,
                ownerName: "skhd",
                ownerBundleID: nil,
                action: commandPart,
                source: .configFile
            )
            bindings.append(binding)
        }

        logger.info("skhd: found \(bindings.count) bindings")
        return bindings
    }

    // MARK: - Key Maps

    /// Maps Karabiner key names to macOS virtual keycodes.
    private let karabinerKeyMap: [String: UInt16] = [
        // Letters
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05,
        "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
        "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11,
        "o": 0x1F, "u": 0x20, "i": 0x22, "p": 0x23, "l": 0x25,
        "j": 0x26, "k": 0x28, "n": 0x2D, "m": 0x2E,

        // Numbers
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17,
        "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19, "0": 0x1D,

        // Special keys
        "return_or_enter": 0x24, "escape": 0x35, "delete_or_backspace": 0x33,
        "tab": 0x30, "spacebar": 0x31, "grave_accent_and_tilde": 0x32,

        // Punctuation
        "hyphen": 0x1B, "equal_sign": 0x18,
        "open_bracket": 0x21, "close_bracket": 0x1E,
        "backslash": 0x2A, "semicolon": 0x29, "quote": 0x27,
        "comma": 0x2B, "period": 0x2F, "slash": 0x2C,

        // Arrow keys
        "left_arrow": 0x7B, "right_arrow": 0x7C,
        "down_arrow": 0x7D, "up_arrow": 0x7E,

        // Function keys
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
        "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
        "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
        "f13": 0x69, "f14": 0x6B, "f15": 0x71,

        // Navigation
        "page_up": 0x74, "page_down": 0x79,
        "home": 0x73, "end": 0x77,
        "delete_forward": 0x75,
    ]

    /// Maps skhd key names to macOS virtual keycodes.
    private let skhdKeyMap: [String: UInt16] = [
        // Letters
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05,
        "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
        "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11,
        "o": 0x1F, "u": 0x20, "i": 0x22, "p": 0x23, "l": 0x25,
        "j": 0x26, "k": 0x28, "n": 0x2D, "m": 0x2E,

        // Numbers
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17,
        "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19, "0": 0x1D,

        // Special keys
        "return": 0x24, "escape": 0x35, "delete": 0x33,
        "tab": 0x30, "space": 0x31,

        // Punctuation
        "-": 0x1B, "=": 0x18,
        "[": 0x21, "]": 0x1E,
        "\\": 0x2A, ";": 0x29, "'": 0x27,
        ",": 0x2B, ".": 0x2F, "/": 0x2C,
        "`": 0x32,

        // Arrow keys
        "left": 0x7B, "right": 0x7C,
        "down": 0x7D, "up": 0x7E,

        // Function keys
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
        "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
        "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
        "f13": 0x69, "f14": 0x6B, "f15": 0x71,

        // Navigation
        "pageup": 0x74, "pagedown": 0x79,
        "home": 0x73, "end": 0x77,
    ]
}
