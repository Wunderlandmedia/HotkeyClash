# Contributing to HotkeyClash

Thanks for your interest in improving HotkeyClash. It is a free, open-source macOS
menu bar app that detects keyboard shortcut conflicts across running apps, automation
tools, and system shortcuts. Issues and pull requests are welcome.

By contributing you agree that your contributions are licensed under the project's
[GPL-2.0](LICENSE) license.

## Ways to contribute

- Report a bug or unexpected conflict result (open an issue)
- Add support for a new shortcut source (see "Adding a scanner" below)
- Improve detection accuracy, key mappings, or the UI
- Improve documentation

### Out of scope (by design)

HotkeyClash is deliberately small. Please do not propose features in these areas, as
they define the boundary of the product:

- Editing or reassigning shortcuts (that is System Settings / KeyCue territory)
- A shortcut cheat-sheet or viewer mode
- Cloud sync, accounts, telemetry, or analytics
- AI features
- Subscriptions, in-app purchases, or any payment
- Network access (other than an optional update check)
- Third-party Swift Package Manager dependencies (Apple frameworks only)

## Getting set up

Requirements:

- macOS 14 (Sonoma) or newer
- Xcode 16 or newer (Swift 6.2+)

Clone and open:

```bash
git clone https://github.com/Wunderlandmedia/HotkeyClash.git
cd HotkeyClash
open HotkeyClash.xcodeproj
```

Build and run from Xcode with Cmd+R, or from the command line:

```bash
xcodebuild -scheme HotkeyClash -configuration Debug build
```

The app runs as a menu bar item (LSUIElement, no Dock icon). To scan running apps you
must grant Accessibility permission in System Settings > Privacy & Security >
Accessibility. Config file and system shortcut scanning work without it.

## How scanning works

A scan is orchestrated by `ShortcutScanner` (`Services/ShortcutScanner.swift`), which
runs three scanners in sequence and merges their output:

1. `SystemShortcutScanner` reads the `com.apple.symbolichotkeys` plist
2. `ConfigFileScanner` reads Karabiner-Elements and skhd config files
3. `MenuBarScanner` traverses running apps' menu bars via the Accessibility API

Every scanner returns `[HotkeyBinding]`. A `HotkeyBinding`
(`Models/HotkeyBinding.swift`) represents one shortcut registration:

| Field | Notes |
|-------|-------|
| `keyCode` | `UInt16` virtual keycode |
| `modifiers` | `NSEvent.ModifierFlags` |
| `ownerName` | Display name of the owning app or tool |
| `ownerBundleID` | Optional; lets the UI show the app icon |
| `action` | Human-readable description of what the shortcut does |
| `source` | `.menuBar`, `.configFile`, or `.systemShortcut` |

All bindings are passed to `ConflictDetector`, which groups them by
`(keyCode, normalizedModifiers)` and classifies each group's severity. Results render
in the master-detail split view (`Views/ConflictListView.swift`).

Key combos are represented as `(keyCode: UInt16, modifiers: NSEvent.ModifierFlags)`
throughout. `ShortcutFormatter` (in `Services/HotKeyManager.swift`) is the single
source of truth for mapping keycodes to display names. Use it rather than hand-rolling
a mapping.

## Adding a scanner

The most common contribution is supporting a new automation tool. There are two cases.

### A new config file (Keyboard Maestro, Hammerspoon, Alfred, etc.)

If the tool stores its shortcuts in a file under the user's home directory, add a parser
to `Services/ConfigFileScanner.swift`:

1. Add a private `scanYourTool() -> [HotkeyBinding]` method, modeled on `scanKarabiner()`
   or `scanSkhd()`.
2. Resolve the path with `expandingTildeInPath`, and `return []` (do not throw) when the
   file is missing, too large, or fails to parse. Reuse the `maxConfigBytes` size guard.
3. Map the tool's key names to virtual keycodes. Reuse or extend an existing key map if
   the format overlaps.
4. Produce `HotkeyBinding` values with `source: .configFile`, a clear `ownerName`, and an
   `action` describing the shortcut.
5. Call your method from `scan()` and append the results.
6. Log a summary with the module `logger` (counts only, never file contents).

### A new source type (a different mechanism)

If the source is not a file under home (for example a SQLite store or a new system API),
add a dedicated service in `Services/` that exposes a `scan()` returning
`[HotkeyBinding]`, then wire it into `ShortcutScanner.runScan()` alongside the existing
scanners. Keep it `@MainActor` and follow the conventions below.

The planned-but-unimplemented sources (Keyboard Maestro, BetterTouchTool, Hammerspoon,
Alfred, Raycast) are good first contributions and are tracked in the roadmap.

## Coding conventions

- One component per file; keep files focused
- All services are `@MainActor` (they touch AppKit/UI)
- Use Swift concurrency (`Task`, `async`/`await`), not GCD (`DispatchQueue`)
- Prefer Apple frameworks over third-party packages, always
- Use modern SwiftUI API: `Tab` (not `tabItem`), `foregroundStyle` (not
  `foregroundColor`), `ContentUnavailableView` for empty states
- `SettingsManager` is `@Observable @MainActor`; bind with `Bindable(settings).property`
- No em dashes in user-facing strings
- No emojis in code or UI
- Fail gracefully: a scanner that hits a missing or malformed source should return an
  empty result and log, never crash the scan
- Do not log file contents or anything that could leak user data; HotkeyClash collects
  nothing and reaches no network

## Commit and pull request workflow

1. Fork the repo and create a topic branch off `main`.
2. Keep commits focused with clear messages.
3. Make sure the project builds cleanly before opening a PR:
   ```bash
   xcodebuild -scheme HotkeyClash -configuration Debug build
   ```
4. Manually verify your change in the running app. If you added a scanner, confirm its
   bindings appear in a scan and that conflicts are detected as expected.
5. Open a pull request describing what changed and why. Reference any related issue.

There is no automated test suite yet, so describe how you verified your change. Pushing
a `v*` tag triggers the release workflow (`.github/workflows/release.yml`); regular PRs
do not.

## Reporting bugs

Open an issue and include:

- macOS version and Mac model
- HotkeyClash version
- What you expected vs. what happened
- If it is a detection issue: the apps or tools involved and the key combo

## License

HotkeyClash is licensed under [GPL-2.0](LICENSE). All contributions are accepted under
the same license.
