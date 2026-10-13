# Licensing

Many Displays is MIT-licensed and anyone can build it from source. The build sold at
manydisplays.com asks for a licence; this is how that works and why it is compatible with open source.

## What the user sees

- The first launch of a release build starts a 14-day trial. Everything works.
- When the trial is over the app keeps tracking windows but stops restoring them, and the menu
  (and a small window) offer to buy or enter a licence.
- A licence is a one-time purchase that includes one year of updates. Versions released inside
  that year work forever; later versions ask to renew (Sparkle does not even offer them).
- One licence can be activated on 3 Macs; "Licence…" in the menu shows the state and lets the
  user remove it from a Mac.

## How it works

- Keys are generated, emailed and validated by Lemon Squeezy (the shop). The app calls their
  public licence API (`/v1/licenses/activate`, `validate`, `deactivate`) with the key and the
  Mac's name; no API secret lives in the app. See `Sources/ManyDisplaysCore/License.swift`.
- The answer (status, `expires_at` = end of the update window, customer email, instance id) is
  stored in UserDefaults and re-checked at most once a week when online, so the app works offline.
- Each release build carries `MDBuildDate` in Info.plist; a licence covers a build when the build
  date is not after the key's `expires_at`.
- `MDRequiresLicense` is only set by `scripts/build-app.sh --dmg`. Builds from source, `swift run`
  and CI artifacts never ask for a licence, so contributors are not nagged.

## Why this is fine for an open-source app

Anyone can build the app without the licence check, or remove it. That is inherent in the MIT
licence and is the model of Maccy, Rectangle or Sublime Text: what is sold is the notarized,
auto-updating build and the support behind it, not the source. The licence check is there to
remind honest users, not to stop determined ones.

## Shop setup (Lemon Squeezy)

Product "Many Displays", one variant, one-time payment, "Generate license keys" on with
activation limit 3 and expiry 1 year. Put the store and product ids in `LemonSqueezy.storeID`
and `productID` so keys from other shops are refused, and the checkout URL in the website's buy page.
