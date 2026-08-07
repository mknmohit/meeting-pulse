#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/Meeting Pulse.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG="$BUILD_DIR/Meeting Pulse.dmg"

: "${MP_SIGN_IDENTITY:?Set MP_SIGN_IDENTITY to the stable Developer ID Application identity}"
: "${MP_TEAM_ID:?Set MP_TEAM_ID to the Apple Developer team identifier}"
: "${MP_NOTARY_PROFILE:?Set MP_NOTARY_PROFILE to a configured notarytool keychain profile}"

if [ ! -f "$ROOT/mac-app/Config.xcconfig" ]; then
  printf '%s\n' "Meeting Pulse: mac-app/Config.xcconfig is required for a release build." >&2
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$EXPORT_DIR"

xcodebuild \
  -project "$ROOT/mac-app/MeetingPulse.xcodeproj" \
  -scheme MeetingPulse \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$MP_TEAM_ID" \
  CODE_SIGN_IDENTITY="$MP_SIGN_IDENTITY" \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$ROOT/mac-app/ExportOptions.plist" \
  -exportPath "$EXPORT_DIR"

hdiutil create \
  -volname "Meeting Pulse" \
  -srcfolder "$EXPORT_DIR/Meeting Pulse.app" \
  -ov \
  -format UDZO \
  "$DMG"

codesign --force --sign "$MP_SIGN_IDENTITY" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$MP_NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG"

printf '%s\n' "$DMG"
