# Security

Many Displays runs with the Accessibility permission, which lets it move windows of other apps.
It makes no network connections except Sparkle update checks, stores data only in
`~/Library/Application Support/ManyDisplays/` and logs to `~/Library/Logs/`.

Things worth knowing:

- `layouts.json` contains window titles (used to re-link windows after an app restarts). It is
  readable only by your user account.
- The `--save`, `--restore` and `--preview-overlay` command-line flags talk to the running app
  through distributed notifications. Any process of the same user can post them; they carry no
  payload and only do what the menu does.
- The app uses a few private macOS symbols (see `Sources/ManyDisplaysCore/Private.swift`). All are
  read-only queries except the Accessibility ones, which are also used by yabai, AltTab and Amethyst.

To report a vulnerability, email the address on [manydisplays.com](https://manydisplays.com) or open
a private security advisory on GitHub. Please do not open a public issue for security problems.
