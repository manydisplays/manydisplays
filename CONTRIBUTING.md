# Contributing

Thanks for helping. Many Displays is small on purpose; please keep it that way.

## Setup

```bash
git clone https://github.com/<you>/many-displays && cd many-displays
swift build && swift test
scripts/build-app.sh --install     # run the real app (asks for Accessibility once)
```

`swiftformat .` before committing (`brew install swiftformat`); CI runs `swiftformat --lint`.

## Before changing restore or snapshot logic

Most past bugs came from saving window frames while macOS was animating them (Space swipes,
Mission Control, the lock-screen shrink). Three rules, all enforced in `Engine.swift`:

1. Never take a snapshot at lock or sleep; the continuous snapshots are already recent.
2. A changed frame is only saved after the app confirms it through its Accessibility frame.
3. Windows on desktops that are not visible cannot have been moved by the user; ignore them.

Test a change with a real sleep/lock/unplug cycle and read `~/Library/Logs/ManyDisplays.log`.
`ManyDisplays --dump` shows what the app sees and what a restore would move.

## Pull requests

- One change per PR, with the "why" in the description (and in a code comment if it is not obvious).
- Pure logic goes in `LayoutMath.swift` or similar and gets a test in `Tests/`.
- New timings or thresholds go in `Tuning.swift` with a one-line reason.
- Keep private API usage inside `Private.swift`, resolved with `dlsym`, with a graceful fallback.

## Reporting bugs

Attach `ManyDisplays --dump` output and the relevant part of the log. Say which monitors you have
and whether "Displays have separate Spaces" is on.
