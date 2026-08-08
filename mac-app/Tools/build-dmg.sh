#!/bin/sh
# Build a polished distributable DMG of Meeting Pulse.
# Uses ad-hoc signing only: no Apple Developer ID or notarization.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
APP_NAME="Meeting Pulse"
APP_BUNDLE="$APP_NAME.app"

: "${MP_DMG_APP:=$ROOT/build/local-arm64-release/Build/Products/Release/$APP_BUNDLE}"
: "${MP_DMG_OUT_DIR:=$ROOT/build/dmg}"
: "${MP_DMG_ASSET_DIR:=$ROOT/build/dmg-assets}"
: "${MP_DMG_STAGE:=$ROOT/build/dmg-stage}"
: "${MP_DMG_VOLUME_NAME:=$APP_NAME Installer}"
: "${MP_DMG_VERSION:=}"
: "${MP_DMG_ARCH:=}"

PLIST="$MP_DMG_APP/Contents/Info.plist"
if [ ! -f "$PLIST" ]; then
  printf '%s\n' "build-dmg: app not found at $MP_DMG_APP — run a Release build first." >&2
  exit 1
fi

if [ -z "$MP_DMG_VERSION" ]; then
  MP_DMG_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")
fi
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")
APP_EXECUTABLE="$MP_DMG_APP/Contents/MacOS/$APP_NAME"
ACTUAL_ARCH=$(lipo -archs "$APP_EXECUTABLE" | tr -d '[:space:]')
if [ -z "$MP_DMG_ARCH" ]; then
  MP_DMG_ARCH="$ACTUAL_ARCH"
fi

case "$MP_DMG_ARCH" in
  arm64|x86_64) ;;
  *)
    printf '%s\n' "build-dmg: unsupported architecture '$MP_DMG_ARCH'." >&2
    exit 1
    ;;
esac

if [ "$ACTUAL_ARCH" != "$MP_DMG_ARCH" ]; then
  printf '%s\n' "build-dmg: expected $MP_DMG_ARCH but app is $ACTUAL_ARCH." >&2
  exit 1
fi

mkdir -p "$MP_DMG_OUT_DIR" "$MP_DMG_ASSET_DIR"

printf '%s\n' "build-dmg: rendering assets"
MP_DMG_APP="$MP_DMG_APP" \
MP_DMG_VERSION="$MP_DMG_VERSION" \
MP_DMG_ASSET_DIR="$MP_DMG_ASSET_DIR" \
python3 "$ROOT/mac-app/Tools/render-dmg-assets.py"

STAGE="$MP_DMG_STAGE"
RW="$MP_DMG_OUT_DIR/.Meeting-Pulse-$MP_DMG_VERSION-$MP_DMG_ARCH.rw.dmg"
FINAL="$MP_DMG_OUT_DIR/Meeting-Pulse-$MP_DMG_VERSION-$MP_DMG_ARCH.dmg"

cleanup() {
  rm -rf "$STAGE"
  rm -f "$RW"
}

trap cleanup EXIT HUP INT TERM
rm -rf "$STAGE"
rm -f "$RW" "$FINAL"
mkdir -p "$STAGE/.background"

cp -R "$MP_DMG_APP" "$STAGE/$APP_BUNDLE"
codesign --force --deep --sign - -o runtime "$STAGE/$APP_BUNDLE"
codesign --verify --deep --strict "$STAGE/$APP_BUNDLE"

ln -s /Applications "$STAGE/Applications"

cp "$MP_DMG_ASSET_DIR/background.png"   "$STAGE/.background/background.png"
if [ -f "$MP_DMG_ASSET_DIR/background@2x.png" ]; then
  cp "$MP_DMG_ASSET_DIR/background@2x.png" "$STAGE/.background/background@2x.png"
fi

cp "$MP_DMG_ASSET_DIR/welcome.html" "$STAGE/Welcome.html"

cp "$MP_DMG_ASSET_DIR/icon-volume.icns" "$STAGE/.VolumeIcon.icns"
SetFile -c icnL "$STAGE/.VolumeIcon.icns" 2>/dev/null || true
SetFile -a V "$STAGE/.VolumeIcon.icns" 2>/dev/null || true

printf '%s\n' "build-dmg: writing Finder layout"
MP_DMG_STAGE="$STAGE" python3 "$ROOT/mac-app/Tools/write-ds-store.py"

SetFile -a B "$STAGE/.background" 2>/dev/null || true
SetFile -a E "$STAGE/.DS_Store" 2>/dev/null || true

printf '%s\n' "build-dmg: creating read-write image"
hdiutil create \
  -volname "$MP_DMG_VOLUME_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDRO \
  -fs HFS+ \
  "$RW"

printf '%s\n' "build-dmg: compressing to $FINAL"
hdiutil convert "$RW" -format UDZO -o "$FINAL"
hdiutil verify "$FINAL" >/dev/null

printf '\n%s\n' "✔ DMG built: $FINAL"
printf '%s\n' "  size:    $(du -h "$FINAL" | awk '{print $1}')"
printf '%s\n' "  version: $MP_DMG_VERSION ($BUILD), arch $MP_DMG_ARCH"
printf '\n%s\n' "Ad-hoc signed only. Gatekeeper will block on first open."
printf '%s\n' "Recipients right-click → Open the first time, or run:"
printf '%s\n' "  xattr -dr com.apple.quarantine \"/Applications/$APP_BUNDLE\""
