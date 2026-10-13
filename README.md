<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Resources/Brand/logo-dark.png">
    <img src="Resources/Brand/logo.png" alt="Many Displays" width="440">
  </picture>
</p>

A macOS menu bar app that remembers where every window lives — which display, which position,
which size, which Space — and puts everything back when your Mac wakes up, unlocks, or
reconnects its external displays.

**[manydisplays.com](https://manydisplays.com)** · Download the notarized build there, or build it yourself (below).

## Why

- macOS identifies displays by their EDID (vendor, model, serial number). Many monitors ship
  with the same serial (`0` or `0x01010101`), so two identical screens are indistinguishable to
  macOS, which shuffles their arrangement and windows after every sleep. As of October 2026
  Apple has not fixed this (see the open threads about identical monitors on macOS 26).
- Even with distinguishable displays, DisplayPort/Thunderbolt monitors "disconnect" when the Mac
  sleeps or locks. macOS piles every window onto whichever display comes back first.
- Existing tools ask every app for every window through Accessibility, which is slow and hangs
  when one app does not respond. Many Displays reads the window server's list instead: around
  20 ms for hundreds of windows, without talking to any app.

## What it does

| Situation | What happens |
|---|---|
| You move, resize, open or close a window | Saved within ~1.5 s (event-driven, no polling), plus a light check every 20 s |
| Lock, sleep, display sleep, displays reconnecting | Saving **freezes** so the mess is never recorded; the last good layout is kept |
| You come back and the displays have been stable for a few seconds | Every window goes back to **its physical display**, position and size. Several quick passes, because macOS keeps nudging windows for a while |
| macOS swapped the arrangement (left ↔ right, main display), the resolution, refresh rate, rotation, HDR, or turned on mirroring after a reconnect | Each one is put back, one step at a time, before the windows (can be turned off in the menu) |
| MacBook alone, no external displays | **Idle**: no observers, no timers |
| Windows you closed while away | Never reopened. New windows are left alone and remembered from then on |
| A display setup never seen before (e.g. same monitors with the lid open) | Restored from the closest saved setup, then remembered separately |
| Undocking leaves the built-in screen at a wrong resolution | The last known good mode is restored. Windows are never touched on the MacBook alone |
| An app or macOS moves a window back right after a restore | For three minutes, changes nobody asked for are undone instead of saved |

One layout is kept **per combination of displays**. Identical monitors that share a serial are told
apart by their system UUID, then by the **physical port** they are plugged into (Apple Silicon),
and only then by position. If a display's resolution changes, positions are scaled proportionally.

"Restore Windows Automatically" (on by default) can be turned off in the menu: the app then keeps
the last good layout, ignores whatever macOS did after a wake or unlock, and waits for
"Restore Windows Now" (`⌃⌥⌘R`). Handy for screen recordings and for checking what the app would do.

While windows are being restored the screens get a soft blur with a countdown (can be turned off).
It only appears when something actually needs to move. A "Close" link appears if it runs past the
usual time, and the veil never stays longer than 10 s.

## Requirements and permissions

- macOS 13 Ventura or later, Apple Silicon or Intel.
- **Accessibility** permission (System Settings → Privacy & Security → Accessibility). Without it,
  positions are still saved but windows cannot be moved.
- No network access, no analytics. The app only talks to Apple's update server when you choose
  "Check for Updates…" or when automatic update checks are enabled (Sparkle).

## Install

Download the DMG from [manydisplays.com](https://manydisplays.com) and drag the app to Applications.
Turn on "Open at Login" from the menu.

To build from source (Xcode 16 or later):

```bash
scripts/build-app.sh --install   # universal build, signed, copied to /Applications and launched
```

The script signs with your "Developer ID Application" certificate if you have one, otherwise
"Apple Development", so the Accessibility permission survives rebuilds. See
[docs/RELEASING.md](docs/RELEASING.md) for packaging, notarization and updates.

## Shortcuts and commands

- `⌃⌥⌘R` restores now (normally you never need it; saving is automatic). Change or disable the
  shortcuts in the menu under Settings → Keyboard Shortcuts…, or with
  `defaults write com.manydisplays.ManyDisplays restoreHotKey -string "ctrl+shift+r"`.
- From Terminal, Shortcuts or Raycast: `/Applications/ManyDisplays.app/Contents/MacOS/ManyDisplays --restore` (or `--save`)
- Preview the blur overlay without moving anything: `… --preview-overlay`
- Diagnostics: `… --dump` prints displays, Spaces, windows and what a restore would move

Data: `~/Library/Application Support/ManyDisplays/layouts.json` (includes window titles, used to
re-link windows after an app restarts) · Log: `~/Library/Logs/ManyDisplays.log`

## Known limitations

- **Spaces.** Since macOS 14.5 Apple blocks moving other apps' windows between Spaces unless SIP is
  disabled; the three known private methods were verified not to work on macOS 26. In practice,
  with "Displays have separate Spaces" turned off, sleeping does not change a window's Space, only
  its display. If a window ends up on a different Space, the menu says so.
- Some apps hide their off-Space windows from Accessibility; those are restored the moment you switch
  to their Space.
- The app relies on a few private macOS symbols (listed in `Private.swift`). They are resolved at
  runtime; if a macOS update removes one, the app keeps running and the log says what is missing.

## How it is built

Swift Package, no Xcode project. `Sources/ManyDisplaysCore` holds everything (so it can be unit
tested); `Sources/ManyDisplays` is a two-line executable. `Engine.swift` is the state machine
(tracking → frozen → restoring), `Tuning.swift` has every timing and threshold with the reason
behind it, `docs/RESEARCH.md` records what was tried and why.

```bash
swift build && swift test
swiftformat --lint .
```

See [CONTRIBUTING.md](CONTRIBUTING.md). Security issues: [SECURITY.md](SECURITY.md).

## License

[Functional Source License, Version 1.1, MIT Future License](LICENSE.md) (FSL-1.1-MIT). You can
read, build, modify and fork the code, use it yourself and contribute back; you cannot use it to
offer a product or service that competes with Many Displays. Two years after each version is
published it becomes MIT-licensed. The notarized, auto-updating build sold at manydisplays.com is
how the project is funded.

The name "Many Displays" and the app icon are trademarks and are not covered by the licence: a
fork must use its own name and icon.
