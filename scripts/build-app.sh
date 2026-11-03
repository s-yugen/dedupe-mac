#!/usr/bin/env bash
# Builds build/Dedupe.app and build/Dedupe.zip from the Swift package.
#
# Usage:
#   ./scripts/build-app.sh            # universal binary (Apple silicon + Intel)
#   UNIVERSAL=0 ./scripts/build-app.sh  # current Mac's architecture only, faster
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Dedupe"
PRODUCT="DedupeMac"
OUT_DIR="build"
APP="$OUT_DIR/$APP_NAME.app"

if [[ "${UNIVERSAL:-1}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
else
  ARCH_FLAGS=()
fi

echo "Building $PRODUCT (release)..."
swift build -c release --product "$PRODUCT" "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}"
BIN_DIR="$(swift build -c release --product "$PRODUCT" "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}" --show-bin-path)"

echo "Assembling $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$PRODUCT" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
fi

# Ad-hoc signature. Apple silicon Macs refuse to run unsigned binaries.
codesign --force --sign - --timestamp=none "$APP"

rm -f "$OUT_DIR/$APP_NAME.zip"
ditto -c -k --keepParent "$APP" "$OUT_DIR/$APP_NAME.zip"

echo "Done:"
echo "  $APP"
echo "  $OUT_DIR/$APP_NAME.zip"
lipo -info "$APP/Contents/MacOS/$APP_NAME" || true
