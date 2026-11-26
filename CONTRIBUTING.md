# Contributing to HotkeyClash

Thanks for your interest in HotkeyClash. It is a free, open-source macOS menu bar
app that detects keyboard shortcut conflicts across running apps, automation tools,
and system shortcuts.

## Issues yes, pull requests no

HotkeyClash is maintained by one person, and I write all of the code myself. That
keeps the app small, consistent, and easy for me to stand behind.

So I don't merge outside pull requests. Please open an issue instead. A good bug
report or feature idea is the most useful thing you can send, and when an issue
leads to a fix I credit the reporter in the commit.

If you already opened a PR, thank you. I'll read it, and if it points at a real
problem I'll fix it myself and credit you.

## Reporting bugs

Open an issue and include:

- macOS version and Mac model
- HotkeyClash version
- What you expected vs. what happened
- If it is a detection issue: the apps or tools involved and the key combo

## Requesting features

Requests for new shortcut sources (another automation tool, another app's config
file) are especially welcome. Say where the tool stores its shortcuts if you know.

### Out of scope (by design)

HotkeyClash is deliberately small. These areas define the boundary of the product:

- Editing or reassigning shortcuts (that is System Settings / KeyCue territory)
- A shortcut cheat-sheet or viewer mode
- Cloud sync, accounts, telemetry, or analytics
- AI features
- Subscriptions, in-app purchases, or any payment
- Network access (other than an optional update check)
- Third-party Swift Package Manager dependencies (Apple frameworks only)

## Building from source

You're free to build, modify, and fork HotkeyClash under the GPL. You need macOS 14
or newer and Xcode 16 or newer.

```bash
git clone https://github.com/Wunderlandmedia/HotkeyClash.git
cd HotkeyClash
xcodebuild -scheme HotkeyClash -configuration Debug build
```

## License

HotkeyClash is licensed under [GPL-2.0](LICENSE).
