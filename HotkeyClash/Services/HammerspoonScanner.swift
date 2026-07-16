import AppKit
import Foundation
import os

// nonisolated so the off-main parser can log too; Logger is Sendable.
private nonisolated let logger = Logger(subsystem: "com.hotkeyclash.app", category: "HammerspoonScanner")

/// Reads Hammerspoon's `init.lua` and extracts the hot keys it registers.
///
/// Hammerspoon is configured in Lua, so there is no plist or database to read
/// cleanly. We do the honest thing a static tool can do: find every
/// `hs.hotkey.bind(...)` call in the source and resolve the arguments that are
/// literals. A bind whose modifiers or key come from a variable
/// (`local hyper = {"cmd", "alt", "ctrl", "shift"}` then `hs.hotkey.bind(hyper, ...)`,
/// a very common pattern) can't be resolved without running the Lua, so we skip
/// it rather than report a shortcut we're not sure about. Better a gap than a
/// phantom conflict.
///
/// We only read `init.lua`; binds that live in `require`d modules aren't
/// followed. That's a deliberate limit, not an oversight - chasing `require`
/// across a user's whole config tree is a different, much larger job.
@MainActor
final class HammerspoonScanner {

    private static let configPath = "~/.hammerspoon/init.lua"

    /// A hand-written Lua config that grows past this is almost certainly not a
    /// config anymore. Same guard the other text-based scanners use.
    private static let maxConfigBytes = 10 * 1024 * 1024

    func scan() async -> [HotkeyBinding] {
        let path = NSString(string: Self.configPath).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else {
            logger.debug("Hammerspoon config not found at \(path)")
            return []
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int, size > Self.maxConfigBytes {
            logger.warning("Hammerspoon config exceeds size limit (\(size) bytes), skipping")
            return []
        }

        let bindings = await Self.loadAndParse(path: path)
        logger.info("Hammerspoon: found \(bindings.count) hot key bindings")
        return bindings
    }

    /// Reads and parses the config off the main actor. Comment stripping and the
    /// call scan are cheap, but a pathologically large config shouldn't be able
    /// to stutter the panel mid-scan, so we keep it off the main thread anyway.
    @concurrent
    private nonisolated static func loadAndParse(path: String) async -> [HotkeyBinding] {
        guard let source = try? String(contentsOfFile: path, encoding: .utf8) else {
            logger.warning("Could not read Hammerspoon config")
            return []
        }
        return parse(source)
    }

    // MARK: - Parsing

    /// Extracts hot key bindings from Lua source. Pure so tests can feed snippets
    /// straight in without touching disk.
    ///
    /// The signature we key off is `hs.hotkey.bind(mods, key, ...)`. Comments are
    /// stripped first so a commented-out bind never counts, then we walk each
    /// call, read its first arguments respecting nesting and quotes, and keep the
    /// ones whose mods and key are both literals we can resolve.
    nonisolated static func parse(_ source: String) -> [HotkeyBinding] {
        let cleaned = Array(stripComments(source))
        let needle = Array("hs.hotkey.bind")

        var bindings: [HotkeyBinding] = []
        var i = 0
        while i <= cleaned.count - needle.count {
            guard matches(cleaned, at: i, needle) else { i += 1; continue }

            // Make sure this is the call, not a longer identifier, and find its
            // opening paren (Lua tolerates whitespace before it).
            guard let openParen = firstOpenParen(cleaned, after: i + needle.count),
                  let (args, closeParen) = readArguments(cleaned, openParenIndex: openParen) else {
                i += needle.count
                continue
            }

            if let binding = binding(fromArguments: args) {
                bindings.append(binding)
            }
            i = closeParen + 1
        }

        return bindings
    }

    /// Builds a binding from the raw argument strings of one `bind` call, or nil
    /// when either the modifiers or the key can't be resolved from literals.
    private nonisolated static func binding(fromArguments args: [String]) -> HotkeyBinding? {
        guard args.count >= 2,
              let modifiers = modifiers(fromModsArgument: args[0].trimmed),
              let keyCode = keyCode(fromKeyArgument: args[1].trimmed) else {
            return nil
        }

        // The optional third argument is a message string Hammerspoon flashes on
        // screen. When it's a literal it makes a far better label than a generic
        // one, so use it; otherwise the key combo has to speak for itself.
        var action = "Hammerspoon hotkey"
        if args.count >= 3, let message = stringLiteralContent(args[2].trimmed), !message.isEmpty {
            action = message
        }

        return HotkeyBinding(
            keyCode: keyCode,
            modifiers: modifiers,
            ownerName: "Hammerspoon",
            ownerBundleID: "org.hammerspoon.Hammerspoon",
            action: action,
            source: .configFile
        )
    }

    // MARK: - Argument resolution

    /// Resolves the modifiers argument. Returns the flag set for a literal table
    /// (`{"cmd", "shift"}`, including the empty `{}`) or a literal string
    /// (`"cmd"`, `"cmd-alt"`). Returns nil when the argument is a variable or
    /// otherwise not a literal, which is the signal to skip the whole bind. A
    /// table that mixes literals with an unquoted identifier (`{hyper, "shift"}`)
    /// counts as unresolvable too, since we'd otherwise silently drop the part we
    /// can't see.
    nonisolated static func modifiers(fromModsArgument raw: String) -> NSEvent.ModifierFlags? {
        if raw.hasPrefix("{") && raw.hasSuffix("}") {
            let inner = Array(raw.dropFirst().dropLast())
            var flags: NSEvent.ModifierFlags = []
            var residual = ""
            var i = 0
            while i < inner.count {
                let c = inner[i]
                if c == "\"" || c == "'" {
                    let (token, next) = readQuoted(inner, openQuoteIndex: i)
                    flags.formUnion(modifierFlags(fromToken: token))
                    i = next
                } else {
                    if !c.isWhitespace && c != "," { residual.append(c) }
                    i += 1
                }
            }
            // Anything alphanumeric left outside the quotes is an unresolvable
            // identifier (a variable, a function call), so we can't trust the set.
            if residual.contains(where: { $0.isLetter || $0.isNumber || $0 == "_" }) {
                return nil
            }
            return flags
        }

        if let string = stringLiteralContent(raw) {
            return modifierFlags(fromToken: string)
        }

        return nil
    }

    /// Resolves the key argument to a virtual keycode. Accepts a string literal
    /// (mapped through the Hammerspoon key names) or a bare integer literal, which
    /// Hammerspoon also allows as a raw keycode. Variables resolve to nil.
    nonisolated static func keyCode(fromKeyArgument raw: String) -> UInt16? {
        if let string = stringLiteralContent(raw) {
            return keyCode(forHammerspoonKey: string)
        }
        if let number = Int(raw), number >= 0, number <= Int(UInt16.max) {
            return UInt16(number)
        }
        return nil
    }

    /// Maps a single Hammerspoon modifier token to a flag. Hammerspoon accepts
    /// several spellings and even the glyphs, and a string argument can pack more
    /// than one modifier together ("cmd-alt"), so we match on substrings.
    nonisolated static func modifierFlags(fromToken token: String) -> NSEvent.ModifierFlags {
        let t = token.lowercased()
        var flags: NSEvent.ModifierFlags = []
        if t.contains("cmd") || t.contains("command") || t.contains("\u{2318}") { flags.insert(.command) }
        if t.contains("shift") || t.contains("\u{21E7}") { flags.insert(.shift) }
        if t.contains("alt") || t.contains("option") || t.contains("opt") || t.contains("\u{2325}") { flags.insert(.option) }
        if t.contains("ctrl") || t.contains("control") || t.contains("\u{2303}") { flags.insert(.control) }
        // "fn" is deliberately ignored: it isn't one of the four modifiers we
        // group conflicts by, and Hammerspoon can't register it as one anyway.
        return flags
    }

    /// Maps a Hammerspoon key name to a virtual keycode. Named keys (return,
    /// space, f-keys, keypad, arrows) come first; a single character falls back
    /// to the ANSI character map the other scanners share.
    nonisolated static func keyCode(forHammerspoonKey key: String) -> UInt16? {
        let k = key.lowercased()
        if let named = namedKeyMap[k] { return named }
        guard k.count == 1 else { return nil }
        return characterKeyMap[k]
    }

    // MARK: - Lua source helpers

    /// Removes Lua comments so a commented-out bind never registers. Handles line
    /// comments (`-- ...`) and block comments (`--[[ ... ]]`, including the
    /// `--[==[ ... ]==]` long-bracket levels), while leaving `--` that appears
    /// inside a string literal alone.
    nonisolated static func stripComments(_ source: String) -> String {
        let chars = Array(source)
        let n = chars.count
        var out: [Character] = []
        out.reserveCapacity(n)
        var i = 0

        while i < n {
            let c = chars[i]

            // Skip over string literals untouched.
            if c == "\"" || c == "'" {
                let quote = c
                out.append(c)
                i += 1
                while i < n {
                    let d = chars[i]
                    if d == "\\" && i + 1 < n {
                        out.append(d)
                        out.append(chars[i + 1])
                        i += 2
                        continue
                    }
                    out.append(d)
                    i += 1
                    if d == quote || d == "\n" { break }
                }
                continue
            }

            // Comments start with `--`.
            if c == "-" && i + 1 < n && chars[i + 1] == "-" {
                let j = i + 2
                // A `[`, optional run of `=`, then `[` opens a block comment.
                if j < n && chars[j] == "[" {
                    var k = j + 1
                    var equals = 0
                    while k < n && chars[k] == "=" { equals += 1; k += 1 }
                    if k < n && chars[k] == "[" {
                        let close = Array("]" + String(repeating: "=", count: equals) + "]")
                        i = k + 1
                        while i < n {
                            if i + close.count <= n && matches(chars, at: i, close) {
                                i += close.count
                                break
                            }
                            i += 1
                        }
                        continue
                    }
                }
                // Otherwise it's a line comment: drop to the newline (keep the
                // newline so line structure is preserved).
                i += 2
                while i < n && chars[i] != "\n" { i += 1 }
                continue
            }

            out.append(c)
            i += 1
        }

        return String(out)
    }

    /// Reads the first arguments of a call starting at its `(`, splitting on
    /// top-level commas while respecting `(){}[]` nesting and quoted strings.
    /// Returns the argument strings and the index of the matching `)`.
    private nonisolated static func readArguments(
        _ chars: [Character],
        openParenIndex: Int
    ) -> (args: [String], closeParen: Int)? {
        var args: [String] = []
        var current = ""
        var depth = 0
        var i = openParenIndex

        while i < chars.count {
            let c = chars[i]

            if c == "\"" || c == "'" {
                let (raw, next) = readQuotedRaw(chars, openQuoteIndex: i)
                current += raw
                i = next
                continue
            }

            switch c {
            case "(", "{", "[":
                depth += 1
                if depth > 1 { current.append(c) }
            case ")", "}", "]":
                depth -= 1
                if depth == 0 {
                    args.append(current)
                    return (args, i)
                }
                current.append(c)
            case "," where depth == 1:
                args.append(current)
                current = ""
            default:
                current.append(c)
            }
            i += 1
        }

        // Ran off the end without a matching close paren: malformed, ignore it.
        return nil
    }

    /// Returns the index of the first `(` after the call name, skipping only
    /// whitespace. Anything else means this wasn't a plain call and we bail.
    private nonisolated static func firstOpenParen(_ chars: [Character], after index: Int) -> Int? {
        var i = index
        while i < chars.count, chars[i].isWhitespace { i += 1 }
        guard i < chars.count, chars[i] == "(" else { return nil }
        return i
    }

    /// True when `needle` appears in `chars` starting exactly at `index`.
    private nonisolated static func matches(_ chars: [Character], at index: Int, _ needle: [Character]) -> Bool {
        guard index + needle.count <= chars.count else { return false }
        for offset in 0..<needle.count where chars[index + offset] != needle[offset] {
            return false
        }
        return true
    }

    /// Reads the content of a quoted string starting at its opening quote,
    /// returning the unquoted, unescaped content and the index just past the
    /// closing quote.
    private nonisolated static func readQuoted(_ chars: [Character], openQuoteIndex: Int) -> (token: String, next: Int) {
        let quote = chars[openQuoteIndex]
        var content = ""
        var i = openQuoteIndex + 1
        while i < chars.count {
            let c = chars[i]
            if c == "\\" && i + 1 < chars.count {
                content.append(chars[i + 1])
                i += 2
                continue
            }
            if c == quote { i += 1; break }
            content.append(c)
            i += 1
        }
        return (content, i)
    }

    /// Like `readQuoted` but keeps the surrounding quotes and raw escapes, for
    /// stitching an argument back together without disturbing its structure.
    private nonisolated static func readQuotedRaw(_ chars: [Character], openQuoteIndex: Int) -> (raw: String, next: Int) {
        let quote = chars[openQuoteIndex]
        var raw = String(quote)
        var i = openQuoteIndex + 1
        while i < chars.count {
            let c = chars[i]
            raw.append(c)
            if c == "\\" && i + 1 < chars.count {
                raw.append(chars[i + 1])
                i += 2
                continue
            }
            i += 1
            if c == quote { break }
        }
        return (raw, i)
    }

    /// Returns the content of a string literal argument (single or double
    /// quoted), or nil when the argument isn't a plain string literal.
    nonisolated static func stringLiteralContent(_ raw: String) -> String? {
        let trimmed = raw.trimmed
        guard trimmed.count >= 2 else { return nil }
        let chars = Array(trimmed)
        let quote = chars[0]
        guard quote == "\"" || quote == "'", chars.last == quote else { return nil }
        let (content, next) = readQuoted(chars, openQuoteIndex: 0)
        // The closing quote has to be the final character; otherwise this is an
        // expression like `"a" .. x`, not a lone literal.
        guard next == chars.count else { return nil }
        return content
    }

    // MARK: - Key maps

    /// Hammerspoon's named keys (`hs.keycodes.map`) mapped to virtual keycodes.
    /// Covers the named keys people actually bind: editing keys, navigation,
    /// function keys, and the numeric keypad.
    nonisolated static let namedKeyMap: [String: UInt16] = [
        "return": 0x24, "enter": 0x24, "tab": 0x30, "space": 0x31,
        "delete": 0x33, "forwarddelete": 0x75, "escape": 0x35, "esc": 0x35,
        "help": 0x72, "home": 0x73, "pageup": 0x74, "end": 0x77, "pagedown": 0x79,
        "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,

        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
        "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
        "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
        "f13": 0x69, "f14": 0x6B, "f15": 0x71, "f16": 0x6A,
        "f17": 0x40, "f18": 0x4F, "f19": 0x50, "f20": 0x5A,

        "pad0": 0x52, "pad1": 0x53, "pad2": 0x54, "pad3": 0x55, "pad4": 0x56,
        "pad5": 0x57, "pad6": 0x58, "pad7": 0x59, "pad8": 0x5B, "pad9": 0x5C,
        "pad.": 0x41, "pad*": 0x43, "pad+": 0x45, "pad/": 0x4B, "pad-": 0x4E,
        "pad=": 0x51, "padclear": 0x47, "padenter": 0x4C,
    ]

    /// ANSI layout keycodes for single characters, matching the maps the other
    /// config scanners use.
    nonisolated static let characterKeyMap: [String: UInt16] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05,
        "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
        "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11,
        "o": 0x1F, "u": 0x20, "i": 0x22, "p": 0x23, "l": 0x25,
        "j": 0x26, "k": 0x28, "n": 0x2D, "m": 0x2E,
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17,
        "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19, "0": 0x1D,
        "-": 0x1B, "=": 0x18, "[": 0x21, "]": 0x1E,
        "\\": 0x2A, ";": 0x29, "'": 0x27,
        ",": 0x2B, ".": 0x2F, "/": 0x2C, "`": 0x32,
    ]
}

private extension String {
    /// Whitespace-trimmed copy. Argument slices arrive with the spacing the user
    /// left around commas, and every consumer here wants it gone first.
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
