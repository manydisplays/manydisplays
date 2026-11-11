# Releasing

## One-time setup

1. **Developer ID certificate.** Xcode → Settings → Accounts → your team → Manage Certificates →
   "+" → Developer ID Application (the Account Holder must do this). Check with
   `security find-identity -v -p codesigning`.
2. **Notarization credentials.** Create an app-specific password at appleid.apple.com, then:
   ```bash
   xcrun notarytool store-credentials ManyDisplays --apple-id <apple id> --team-id <team id>
   ```
3. **Sparkle keys.** Regenerated on 2026-11-11 after the original private key (from 2026-10-13,
   public key `X3rtvmoCGImCrjZ9Kjz0+XsSYtYDmedaAZmkxKW2YD8=`) was lost with a reformatted Mac.
   Installs up to 1.1.6 still accept updates signed with the new key through Sparkle's key
   rotation: the app keeps the same Developer ID team (`5VHM3LM8C2`), so only the EdDSA key
   changes. Never change the Developer ID team and the EdDSA key in the same release.
   The private key lives in the login Keychain of the build Mac ("Private key for signing Sparkle
   updates"); the public key is `aFS7/8UtWFY5H489txU3rsjbk1TMThGeXSeT2m1Ya0Y=` and is the default
   in `scripts/build-app.sh`. Keep a backup outside the Mac (`generate_keys -x file`, import with
   `generate_keys -f file`): losing it again means another rotation. Never commit that file.

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
