#!/bin/bash
# Builds Many Displays.app (universal), signs it, and optionally packages, notarizes and installs it.
#
# Usage: scripts/build-app.sh [--install] [--dmg] [--notarize]
#   --install   copies the app to /Applications and (re)launches it
#   --dmg       also builds build/ManyDisplays-<version>.dmg
#   --notarize  submits the DMG to Apple (implies --dmg), waits, and staples the ticket
#
# Environment:
#   CODESIGN_IDENTITY   signing identity; default: "Developer ID Application" if present,
#                       otherwise "Apple Development", otherwise ad-hoc ("-")
#   NOTARY_PROFILE      notarytool keychain profile (default: ManyDisplays); create it once with
#                       xcrun notarytool store-credentials ManyDisplays --apple-id <id> --team-id <team>
#   SPARKLE_FEED_URL    appcast URL (default: https://manydisplays.com/appcast.xml)
#   SPARKLE_PUBLIC_KEY  EdDSA public key printed by Sparkle's generate_keys (default: the project key)
#   SPARKLE=1           turn on "Check for Updates…" in a plain build (it is on for --dmg/--notarize)
#   VERSION             marketing version (default: latest git tag without "v", or 0.0.0)
set -euo pipefail
cd "$(dirname "$0")/.."

INSTALL=false; DMG=false; NOTARIZE=false
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://manydisplays.com/appcast.xml}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-X3rtvmoCGImCrjZ9Kjz0+XsSYtYDmedaAZmkxKW2YD8=}"
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=true ;;
        --dmg) DMG=true ;;
        --notarize) NOTARIZE=true; DMG=true ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

swift build -c release --arch arm64 --arch x86_64
PRODUCTS=.build/apple/Products/Release

APP=build/ManyDisplays.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$PRODUCTS/ManyDisplays" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R "$PRODUCTS/Sparkle.framework" "$APP/Contents/Frameworks/"
# SwiftPM links Sparkle through @rpath; point it at the bundle's Frameworks folder.
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/ManyDisplays" 2>/dev/null || true

PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :MDBuildDate string $(date -u +%Y-%m-%d)" "$PLIST"
if $DMG; then
    # Only the distributed build asks for a licence; builds from source run free.
    /usr/libexec/PlistBuddy -c "Add :MDRequiresLicense bool true" "$PLIST"
fi
if $DMG || [[ "${SPARKLE:-0}" == "1" ]]; then
    /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SPARKLE_FEED_URL" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_KEY" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :SUEnableInstallerLauncherService bool false" "$PLIST"
fi

# Signing. A stable identity keeps the Accessibility permission across rebuilds (ad-hoc
# signatures change every build and macOS would ask again). Developer ID is required to
# distribute outside the App Store; notarization also needs the hardened runtime + timestamp.
pick_identity() {
    security find-identity -v -p codesigning | awk -v kind="$1" 'index($0, kind) {print $2; exit}'
}
IDENTITY="${CODESIGN_IDENTITY:-$(pick_identity "Developer ID Application")}"
IDENTITY="${IDENTITY:-$(pick_identity "Apple Development")}"
IDENTITY="${IDENTITY:--}"
SIGN=(codesign --force --options runtime --sign "$IDENTITY")
[[ "$IDENTITY" != "-" ]] && SIGN+=(--timestamp)

# Sparkle's nested helpers must be signed before the framework and the framework before the app.
FW="$APP/Contents/Frameworks/Sparkle.framework"
for nested in "$FW/Versions/B/XPCServices/Installer.xpc" "$FW/Versions/B/XPCServices/Downloader.xpc" \
              "$FW/Versions/B/Autoupdate" "$FW/Versions/B/Updater.app"; do
    [[ -e "$nested" ]] && "${SIGN[@]}" "$nested"
done
"${SIGN[@]}" "$FW"
"${SIGN[@]}" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP $VERSION ($BUILD_NUMBER), signed with ${IDENTITY}"
if [[ "$IDENTITY" != *"Developer ID"* ]] && ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "Note: no 'Developer ID Application' certificate in the keychain; this build cannot be notarized or distributed."
fi

if $DMG; then
    DMG_PATH="build/ManyDisplays-$VERSION.dmg"
    rm -f "$DMG_PATH"
    # dmgbuild writes the window layout (background, icon positions, no toolbar) straight into
    # the image, without scripting Finder. It lives in a venv under .build/.
    DMGBUILD=.build/dmgbuild-venv/bin/dmgbuild
    if [[ ! -x "$DMGBUILD" ]]; then
        python3 -m venv .build/dmgbuild-venv
        .build/dmgbuild-venv/bin/pip install --quiet "dmgbuild==1.6.7"
    fi
    "$DMGBUILD" -s scripts/dmg-settings.py -D app="$APP" "Many Displays" "$DMG_PATH" >/dev/null
    "${SIGN[@]}" "$DMG_PATH"
    echo "Packaged $DMG_PATH"
    if $NOTARIZE; then
        xcrun notarytool submit "$DMG_PATH" --keychain-profile "${NOTARY_PROFILE:-ManyDisplays}" --wait
        xcrun stapler staple "$DMG_PATH"
        xcrun stapler staple "$APP"
        echo "Notarized and stapled"
    fi
fi

if $INSTALL; then
    pkill -x ManyDisplays 2>/dev/null && sleep 0.5 || true
    rm -rf /Applications/ManyDisplays.app
    cp -R "$APP" /Applications/
    open /Applications/ManyDisplays.app
    echo "Installed in /Applications and launched"
fi
