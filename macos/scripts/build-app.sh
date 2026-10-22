#!/bin/bash
# Builds "build/Santo Video Player.app" from the Swift package.
# Usage: scripts/build-app.sh [--install]   (--install copies it to /Applications)
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Santo Video Player"
BUNDLE="$PWD/build/$APP_NAME.app"
# SwiftUI macros (@State, @Observable) need Xcode's toolchain, not the CLT.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if swift build -c release --arch arm64 --arch x86_64; then
    BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
else
    echo "Universal build unavailable; building for $(uname -m) only."
    swift build -c release
    BIN_DIR="$(swift build -c release --show-bin-path)"
fi

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_DIR/SantoPlayer" "$BUNDLE/Contents/MacOS/SantoPlayer"
# SwiftPM stamps the deployment target as the SDK version, which runs the app
# in the old look on new macOS (no Liquid Glass). Stamp the real SDK.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
if [ -n "$SDK_VERSION" ]; then
    vtool -set-build-version macos 15.0 "$SDK_VERSION" -replace \
        -output "$BUNDLE/Contents/MacOS/SantoPlayer" "$BUNDLE/Contents/MacOS/SantoPlayer"
fi
cp Support/Info.plist "$BUNDLE/Contents/Info.plist"
# Translations: one <lang>.lproj per language (keys are the Portuguese strings).
cp -R Support/Localizations/*.lproj "$BUNDLE/Contents/Resources/"

# A ready-made Assets/AppIcon.icns wins; otherwise render one from AppIcon.png.
if [[ -f Assets/AppIcon.icns ]]; then
    cp Assets/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
else
    ICONSET="$PWD/build/AppIcon.iconset"
    rm -rf "$ICONSET"
    swift scripts/make-icon.swift Assets/AppIcon.png "$ICONSET"
    iconutil -c icns "$ICONSET" -o "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

codesign --force --options runtime --sign - "$BUNDLE"
echo "Built $BUNDLE"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$BUNDLE" "/Applications/"
    echo "Installed /Applications/$APP_NAME.app"
fi
