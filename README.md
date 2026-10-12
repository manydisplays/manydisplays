# ManyDisplays

A menu bar app (no Dock icon) that keeps track of every window's display, position, size and
Space in near real time, and puts everything back automatically when your Mac wakes from sleep,
unlocks, or when you reconnect your external displays.

## Why it exists

- macOS identifies each display by its EDID (vendor, model, serial number, manufacture date).
  When two identical monitors report the same serial (many send `0` or `0x01010101`), macOS
  cannot tell them apart and shuffles the arrangement and the windows after waking up.
  **As of October 2026 Apple has not fixed this**: there are open threads on the Apple
  Developer Forums about identical monitors on macOS 26 (Tahoe).
- Even when the monitors *can* be told apart, DisplayPort/Thunderbolt displays "disconnect"
  when the Mac sleeps or locks. macOS piles every window onto whichever display comes back first
  and never moves them back.
- Existing tools like Stay save layouts by asking every app for every window over Accessibility,
  which is slow and hangs when one app does not respond. ManyDisplays reads the window server's
  window list instead: ~20 ms for hundreds of windows, without talking to any app.

## How it works

| Situation | What happens |
|---|---|
| You move, resize, open or close a window | Saved within ~1.5 s (event-driven, no polling), plus a light check every 20 s |
| Lock, sleep, display sleep, displays reconnecting | Takes a last snapshot and **freezes** saving so the mess is never recorded |
| You come back (unlock / wake) and the displays have been stable for a few seconds | Restores every window to **its physical display** (matched by serial number), position and size. Runs 3 passes because macOS keeps nudging windows for a while |
| macOS swapped the display arrangement (left ↔ right or the main display) | Puts the saved arrangement back (can be turned off in the menu) |
| MacBook alone, no external displays | **Idle**: no observers, no timers |
| You closed windows while working on the MacBook alone | They are never reopened: only windows that still exist are moved; closed ones are forgotten |
| New windows opened in the meantime | Left alone, and tracked from then on |
| A display setup never seen before (e.g. same monitors with the lid open) | Restores from the closest saved setup, then tracks the new one separately |

One layout is kept **per combination of displays** (identified by vendor, model and serial;
duplicated serials fall back to the display UUID and then to position). If the resolution
changes, positions are scaled proportionally.

While windows are being restored the screens get a subtle blur with a small spinner (can be
turned off in the menu). It only appears when something actually needs to move, never on the
MacBook alone. A "Close" link appears after 4 s and the veil is removed after 15 s at most.

Data: `~/Library/Application Support/ManyDisplays/layouts.json` · Log: `~/Library/Logs/ManyDisplays.log`

## Install

```bash
scripts/build-app.sh --install   # builds, signs, copies to /Applications and launches it
```

On first launch it asks for **Accessibility** (System Settings → Privacy & Security →
Accessibility → ManyDisplays). Without it, positions are still saved but windows cannot be moved.
The app is signed with your "Apple Development" certificate so the permission survives rebuilds.
Enable "Open at Login" from the menu.

## Shortcuts and commands

- `⌃⌥⌘R` restore now · `⌃⌥⌘S` save now (normally you need neither)
- From Terminal / Shortcuts / Raycast: `/Applications/ManyDisplays.app/Contents/MacOS/ManyDisplays --restore` (or `--save`)
- Preview the blur overlay without moving anything: `.../ManyDisplays --preview-overlay`
- Diagnostics: `.../ManyDisplays --dump` prints displays, Spaces, windows and what a restore would move

## Known limitation: Spaces

Since macOS 14.5 Apple blocks moving **other apps'** windows between Spaces unless SIP is
disabled. Verified on macOS 26.6 with the three known private methods
(`CGSMoveWindowsToManagedSpace`, `SetWindowListWorkspace` with a compat ID, and
`Add/RemoveWindowsFromSpaces`): none of them work. In practice it rarely matters: with
"Displays have separate Spaces" turned off, sleeping does not change a window's Space, it only
shuffles windows between displays. If a window ends up on a different Space, the menu says so.

Windows on other Spaces are put back without visiting them. Some apps hide off-Space windows
from Accessibility; those are restored as soon as you switch to their Space.
