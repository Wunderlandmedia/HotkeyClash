# Security Policy

## Supported versions

HotkeyClash ships as notarized DMG and ZIP builds. Only the latest release
receives security fixes. Please update to the newest version before reporting an
issue.

## Reporting a vulnerability

Report security issues privately. Do not open a public issue for a suspected
vulnerability.

- Preferred: use GitHub's private vulnerability reporting on this repository
  (the Security tab, then "Report a vulnerability").
- Or email: info@wunderlandmedia.com

Please include:

- The HotkeyClash version and your macOS version
- A description of the issue and its impact
- Steps to reproduce, and a proof of concept if you have one

We aim to acknowledge reports within a few days and will keep you updated as we
investigate. When a fix ships we are glad to credit you in the release notes,
unless you prefer to stay anonymous.

## Design notes

HotkeyClash is built to keep its attack surface small:

- It uses the macOS Accessibility API to read menu bar shortcuts, which is why
  it runs unsandboxed. It reads shortcut data only and does not record or
  transmit keystrokes.
- It makes no network connections, has no accounts, and collects no telemetry.
- It has zero third-party dependencies and uses only Apple frameworks.

Reports that require the user to first disable these protections, or that assume
local admin or physical access to an unlocked Mac, are generally out of scope.
