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

This produces `build/ManyDisplays-1.1.0.dmg`, notarized and stapled. Then:

```bash
.build/artifacts/sparkle/Sparkle/bin/sign_update build/ManyDisplays-1.1.0.dmg   # prints the appcast attributes
```

Add an `<item>` to `appcast.xml` with the version, the DMG URL, the `sparkle:edSignature` and
`length` printed above, and upload both the DMG and the appcast to manydisplays.com.

Update `CHANGELOG.md` before tagging; the release notes can point at it.
