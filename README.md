<h1 align="center">HotkeyClash</h1>

<p align="center">
  <i>Find where your keyboard shortcuts clash.</i>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-blue?style=flat-square" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6.2-orange?style=flat-square&logo=swift&logoColor=white" alt="Swift 6.2">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--2.0-green?style=flat-square" alt="GPL-2.0"></a>
  <img src="https://img.shields.io/badge/dependencies-0-brightgreen?style=flat-square" alt="Zero dependencies">
</p>

<p align="center">
  <a href="https://www.producthunt.com/products/hotkeyclash?embed=true&amp;utm_source=badge-featured&amp;utm_medium=badge&amp;utm_campaign=badge-hotkeyclash" target="_blank" rel="noopener noreferrer"><img alt="HotkeyClash - Find where your Mac keyboard shortcuts clash | Product Hunt" width="250" height="54" src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=1178712&amp;theme=light&amp;t=1782223133628"></a>
</p>

<!--
<p align="center">
  <img src=".github/assets/screenshot.png" alt="HotkeyClash screenshot" width="680">
</p>
-->

Open-source macOS menu bar utility that scans running apps, config files, and system shortcuts to detect keyboard shortcut conflicts. Master-detail split view shows every clash at a glance.

## Features

- Scans running apps' menu bar shortcuts via Accessibility API
- Parses Karabiner-Elements and skhd config files
- Reads macOS system shortcuts (Spotlight, Mission Control, Screenshots, etc.)
- Classifies conflicts as definite (global vs global) or potential (menu vs menu)
- 720x520 split view: conflict sidebar + detail pane with app icons and source badges
- Zero external dependencies. Pure Apple frameworks.

## Install

### Homebrew

```bash
brew install --cask wunderlandmedia/tap/hotkeyclash
```

To update later: `brew upgrade --cask hotkeyclash`.

### Download

Grab the latest DMG or ZIP from [Releases](https://github.com/Wunderlandmedia/HotkeyClash/releases).

### Build from source

```bash
git clone https://github.com/Wunderlandmedia/HotkeyClash.git
cd HotkeyClash
xcodebuild -scheme HotkeyClash -configuration Release build
```

Requires Xcode 16+ and macOS 14+.

### Build a release (DMG + ZIP)

```bash
# Local build (skip notarization)
./scripts/build-release.sh --skip-notarize

# Full notarized release (after one-time Keychain setup)
./scripts/build-release.sh
```

Artifacts land in `build/release/`.

## What it scans

| Source | Method |
|--------|--------|
| Running apps | Accessibility API (AXMenuBar traversal) |
| Karabiner-Elements | `~/.config/karabiner/karabiner.json` |
| skhd | `~/.config/skhd/skhdrc` |
| macOS system shortcuts | `com.apple.symbolichotkeys` plist |

Accessibility permission is required to scan running apps. Config files and system shortcuts work without it.

## Planned

- Keyboard Maestro, BetterTouchTool, Hammerspoon, Alfred, Raycast parsers
- Real-time "test this shortcut" mode (press a combo, see which app catches it)
- Export conflict report as Markdown
- Auto-rescan on app launch/quit

## Also by Wunderlandmedia

- [QuietClip](https://quietclip.app) -- Privacy-first clipboard manager for macOS
- [WunderType](https://wunderpen.com) -- AI text correction via keyboard shortcuts

## Contributing

Issues and pull requests welcome. Each config file parser is a self-contained method in `ConfigFileScanner.swift`, making it straightforward to add support for new tools.

## License

[GPL-2.0](LICENSE)
