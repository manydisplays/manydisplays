# Releasing

## One-time setup

1. **Developer ID certificate.** Xcode → Settings → Accounts → your team → Manage Certificates →
   "+" → Developer ID Application (the Account Holder must do this). Check with
   `security find-identity -v -p codesigning`.
2. **Notarization credentials.** Create an app-specific password at appleid.apple.com, then:
   ```bash
   xcrun notarytool store-credentials ManyDisplays --apple-id <apple id> --team-id <team id>
   ```
3. **Sparkle keys.** Already generated on 2026-10-13 with `generate_keys` (found in
   `.build/artifacts/sparkle/Sparkle/bin/` after any build). The private key lives in the login
   Keychain of the build Mac ("Private key for signing Sparkle updates"); the public key is
   `X3rtvmoCGImCrjZ9Kjz0+XsSYtYDmedaAZmkxKW2YD8=` and is the default in `scripts/build-app.sh`.
   Back the private key up somewhere safe (`generate_keys -x sparkle-private-key.txt`): losing it
   means existing installs can never update again. Never commit that file.

## Each release

```bash
git tag v1.1.0 && git push --tags
scripts/build-app.sh --notarize
```

This produces `build/ManyDisplays-1.1.0.dmg`, notarized and stapled. The DMG window (background, icon positions) is
built by [dmgbuild](https://dmgbuild.readthedocs.io), installed on first use in a venv under
`.build/`; the background is `Resources/DMG/background.tiff`, drawn by
`swift scripts/make-dmg-background.swift` (icon centres must match `scripts/dmg-settings.py`). Then:

```bash
.build/artifacts/sparkle/Sparkle/bin/sign_update build/ManyDisplays-1.1.0.dmg   # prints the appcast attributes
```

Publish the GitHub release. The website links `releases/latest/download/ManyDisplays.dmg`, so the
asset must be uploaded under that fixed name (the versioned name is kept as a second asset):

```bash
cp build/ManyDisplays-1.1.0.dmg build/ManyDisplays.dmg
gh release create v1.1.0 build/ManyDisplays.dmg build/ManyDisplays-1.1.0.dmg --title "Many Displays 1.1.0" --notes-file <(sed -n '/^## \[1.1.0\]/,/^## \[/p' CHANGELOG.md | sed '$d')
```

Then add an `<item>` to `appcast.xml` in the website repo (local checkout at
`../many-displays-website`) with the version, the URL of the versioned DMG, the
`sparkle:edSignature` and `length` printed by `sign_update`, and push it: GitHub Pages serves
https://manydisplays.com/appcast.xml.

Update `CHANGELOG.md` before tagging; the release notes can point at it.
