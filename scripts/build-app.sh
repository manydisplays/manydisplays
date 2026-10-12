#!/bin/bash
# Builds ManyDisplays.app. Usage: scripts/build-app.sh [--install]
#   --install  copies it to /Applications and (re)launches it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64

APP=build/ManyDisplays.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/arm64-apple-macosx/release/ManyDisplays "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"

# A stable signing identity keeps the Accessibility permission across rebuilds
# (ad-hoc signatures change every build and macOS would ask again).
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')}"
codesign --force --options runtime --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed with ${IDENTITY:-ad-hoc})"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x ManyDisplays 2>/dev/null && sleep 0.5 || true
    rm -rf /Applications/ManyDisplays.app
    cp -R "$APP" /Applications/
    open /Applications/ManyDisplays.app
    echo "Installed in /Applications and launched"
fi
