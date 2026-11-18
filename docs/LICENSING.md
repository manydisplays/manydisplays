# Licensing

Many Displays is published under the Functional Source License (FSL-1.1-MIT) and anyone can build it from source for their own use. The build sold at
manydisplays.com asks for a licence; this is how that works and why it is compatible with open source.

## What the user sees

- The first launch of a release build starts a 14-day trial. Everything works.
- When the trial is over the app keeps tracking windows but stops restoring them, and the menu
  (and a small window) offer to buy or enter a licence.
- A licence is a one-time purchase that includes one year of updates. Versions released inside
  that year work forever; later versions ask to renew (Sparkle does not even offer them).
- The key is shown right after checkout and emailed; "Licence…" in the menu shows the state.

## How it works

- A key is `MD1.<payload>.<signature>`: the payload is `email|issued|updatesUntil` and the
  signature is Ed25519 over it. The app carries only the public key
  (`Licensing.publicKeysBase64`, newest first) and verifies offline; it never calls home.
  See `Sources/ManyDisplaysCore/License.swift`.
- The private key lives in the shop backend (`LICENSE_PRIVATE_KEY`), in the maintainer's
  Keychain (account `manydisplays`, service "Many Displays licence signing key (Ed25519 private,
  base64)") and in the off-Mac credentials backup. The shop issues a key when Stripe reports a completed
  checkout; `scripts/license-tool.swift sign` issues one by hand (support, refunds, gifts).
- Each release build carries `MDBuildDate` in Info.plist; a licence covers a build when the build
  date is not after the key's `updatesUntil`.
- `MDRequiresLicense` is only set by `scripts/build-app.sh --dmg`. Builds from source, `swift run`
  and CI artifacts never ask for a licence, so contributors are not nagged.
- Rotating the key pair: generate a new one (`license-tool.swift generate-keys`), put its public
  key first in `publicKeysBase64` and keep the old ones so existing keys stay valid. Switch the
  shop's `LICENSE_PRIVATE_KEY` only once a release that accepts the new key is out.
- Rotated on 2026-11-18: the private half of `fatp+ja2…` was lost with a reformatted Mac (it only
  survives as the shop's write-only secret). The new key is `zxiLMSNj…`.

## Why this is fine for a source-available app

Anyone can build the app for themselves without the licence check, or remove it; the FSL only
forbids using the code for a competing product or service. What is sold is the notarized,
auto-updating build and the support behind it, not the source, as with Maccy, Rectangle or
Sublime Text. The licence check is there to remind honest users, not to stop determined ones.
Keys cannot be forged without the private key.

## Shop

Stripe Managed Payments (Stripe is the merchant of record and handles VAT/sales tax). The
checkout's success page and a webhook are served by a small worker in the `shop` repository,
which signs the key with the private key, shows it, and emails it.
