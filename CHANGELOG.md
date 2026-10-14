# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- A welcome window on first launch explains what the app does and why it needs the Accessibility permission, before macOS asks for it. "Not Now" keeps it closed until the next update; the menu reopens it.

### Changed
- Without the Accessibility permission the menu shows an orange "Accessibility permission needed" status, the menu bar icon is dimmed, and "Grant Accessibility Permission…" opens the welcome window. Turning the permission off while the app runs is detected too, and granting it again resumes without a restart.

## [1.1.4] - 2026-10-14

### Fixed
- During the three minutes after a restore, a snapshot taken while the mouse or keyboard is in use is postponed instead of saving positions that macOS may still be changing.

## [1.1.3] - 2026-10-14

### Changed
- Licence window shows an "Activated" state with Remove Licence and Done once a key is in; the status line shows an expired trial in orange instead of a green "tracking"; "remembering" replaces "tracking" in the interface.

### Fixed
- ⌘V, ⌘C and ⌘A work in the licence window (menu bar apps need an Edit menu for that).

## [1.1.2] - 2026-10-14

### Added
- Settings → Reset Settings to Defaults… (keeps the licence, the saved layouts and the login item).

### Fixed
- Windows of a busy app (Finder with many windows open) could be written off as unreachable after a single Accessibility timeout and never restored again. The lookup now retries with more time, a window is only given up after three misses, the mark is cleared as soon as the app reports the window, and the log says what happened.
- Chrome's small helper strips are no longer saved, so they never show up as "windows will be restored when you visit their Space".
- "Save Current Layout" no longer puts windows back to their previously restored position (the post-restore drift guard is cleared by a manual save), so saving never moves or resizes anything.
- "Restore Windows Now" and "Save Current Layout" work while tracking is paused; the pause only stops the automatic saving and restoring.

### Added
- Settings → "Restore Windows Automatically" (on by default). Off, the app holds after a wake, unlock or reconnect without saving the shuffled layout, until "Restore Windows Now" or its shortcut.

## [1.1.1] - 2026-10-13

### Changed
- Menu bar icon is always the app's face; it dims when idle or paused.
- Menu reorganised: status dot, daily actions on top, Settings and Help submenus, About opens manydisplays.com.
- "Save Positions Now" is now "Save Current Layout" and has no default shortcut (saving is automatic).
- Keyboard shortcuts can be changed or disabled in Settings → Keyboard Shortcuts…; changes apply immediately.
- Licence is the Functional Source License (FSL-1.1-MIT) instead of MIT.

## [1.1.0] - 2026-10-13

### Added
- Licensing for the distributed build: 14-day trial, offline-verified Ed25519 licence keys issued after a Stripe checkout, one year of updates per licence (see docs/LICENSING.md). Builds from source stay free.
- Unit tests for the pure logic (frame scaling, closest layout, window re-linking, display fixes, shortcut parsing).
- Configurable global shortcuts through `defaults write` (`restoreHotKey`, `saveHotKey`).
- Sparkle updates ("Check for Updates…"), enabled in release builds that carry a feed URL and public key.
- Universal (Apple Silicon + Intel) build, DMG packaging and notarization in `scripts/build-app.sh`.
- App icon and logo (`Resources/AppIcon.svg` is the master; `scripts/make-icon.swift` and `scripts/make-logo.swift` render the icns, PNGs and wordmark), CI (build, test, lint), CONTRIBUTING, SECURITY, CODE_OF_CONDUCT.

### Changed
- The menu bar icon while tracking is the app's own mark (two displays) instead of a generic split rectangle.
- Bundle identifier is now `com.manydisplays.ManyDisplays` (macOS will ask for Accessibility once more).
- System windows (Control Center, Dock, Spotlight…) are excluded by bundle identifier, so it works in every language.
- Private macOS symbols are resolved at runtime; a missing one no longer prevents the app from launching.
- Mirroring is only turned off after a display (re)connection, never after a plain unlock.
- All timings and thresholds live in `Tuning.swift`.

### Fixed
- An unresponsive app could stall the engine for over a minute during a deep window scan.
- Re-linking windows after an app restart scanned apps one by one; now in parallel.
- Log file is kept open instead of reopened for every line.

## [1.0.0] - 2026-10-13

First private release: tracking, restore after sleep/lock/reconnect, display arrangement, rotation,
resolution and HDR fixes, blur overlay, drift guard, Spaces awareness.
